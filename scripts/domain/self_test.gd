extends SceneTree
## Прогон модели без окна: цилиндр должен ехать от давления, площади и линий,
## а не от заранее заданной анимации.

const CircuitScript = preload("res://scripts/domain/circuit.gd")
const Geom = preload("res://scripts/domain/symbol_geom.gd")
const Iso = preload("res://scripts/view3d/iso_cylinder.gd")
const SceneBuilder = preload("res://scripts/domain/scene_builder.gd")
const ElecNet = preload("res://scripts/domain/electrical_network.gd")
const SchematicLayout = preload("res://scripts/domain/schematic_layout.gd")
const Rail2D = preload("res://scripts/domain/rail_2d.gd")
const ElectroLib = preload("res://scripts/domain/electro_library.gd")


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var code := 0
	if not _check_flow():
		code = 1
	if not _check_motion():
		code = 1
	if not _check_symbol_and_mesh():
		code = 1
	if not _check_areas():
		code = 1
	if not _check_realism_wave():
		code = 1
	if not _check_valve():
		code = 1
	if not _check_valve_library():
		code = 1
	if not _check_accessories():
		code = 1
	if not _check_valve_nc_blocks():
		code = 1
	if not _check_lamp_needs_return():
		code = 1
	if not _check_electro_sim_topology():
		code = 1
	if not _check_electro_ports_on_grid():
		code = 1
	if not _check_rail_and_layout():
		code = 1
	if code == 0:
		print("SELF-TEST PASS")
	else:
		print("SELF-TEST FAIL")
	quit(code)


func _check_areas() -> bool:
	var circuit = CircuitScript.new()
	var cylinder = circuit.add_element("cylinder", Vector2.ZERO)
	cylinder.bore_mm = 32.0
	cylinder.rod_mm = 12.0
	circuit.retune_geometry(cylinder)
	var force: float = circuit.drive_force(cylinder, 5.0e5 + 101325.0, 10.0e5 + 101325.0)
	print("areas 5bar cap / 10bar rod => %.1f N" % force)
	if force >= 0.0:
		print("FAIL smaller annulus should retract")
		return false
	cylinder.rod_mm = 80.0
	var note: String = circuit.retune_geometry(cylinder)
	print("rod clamp %.1f note=%s" % [cylinder.rod_mm, note])
	if cylinder.rod_mm != 12.0 or note == "":
		print("FAIL generic rod should snap to 12 mm")
		return false
	cylinder.bore_mm = 40.0
	cylinder.rod_mm = 12.0
	circuit.retune_geometry(cylinder)
	if cylinder.rod_mm != 12.0:
		print("FAIL compact 12 mm rod at bore 40 is a real ISO 21287 size")
		return false
	cylinder.rod_mm = 16.0
	circuit.retune_geometry(cylinder)
	if cylinder.rod_mm != 16.0:
		print("FAIL profile 16 mm rod at bore 40 is a real ISO 15552 size")
		return false
	cylinder.spring_side = "both"
	var invented: String = circuit.retune_geometry(cylinder)
	if not "обеих" in invented:
		print("FAIL two springs should be reported")
		return false
	return true


func _check_flow() -> bool:
	var choked := CircuitScript.mass_flow(7.0e5, 1.0e5, 1.0e-6, 293.15)
	var mild := CircuitScript.mass_flow(2.0e5, 1.5e5, 1.0e-6, 293.15)
	var still := CircuitScript.mass_flow(2.0e5, 2.0e5, 1.0e-6, 293.15)
	print("flow choked=%.6f mild=%.6f still=%.6f" % [choked, mild, still])
	return choked > mild and mild > 0.0 and absf(still) < 1.0e-9


func _check_motion() -> bool:
	var ok := true
	var open = _run_case(false, 0.0, "double", 6.0, 2.5)
	print("open x=%.1f mm p_rod=%.2f bar v=%.3f" % [open.x * 1000.0, _bar(open.p_rod), open.v])
	if open.x < 0.09 or not _finite(open):
		print("FAIL open stroke")
		ok = false
	var stalled = _run_case(false, 2500.0, "double", 6.0, 1.5)
	print("overload x=%.2f mm" % (stalled.x * 1000.0))
	if stalled.x > 0.004:
		print("FAIL overload should not extend")
		ok = false
	var sealed = _run_case(true, 0.0, "double", 6.0, 3.0)
	print("sealed x=%.1f mm p_rod=%.2f bar" % [sealed.x * 1000.0, _bar(sealed.p_rod)])
	if _bar(sealed.p_rod) < 1.2 or sealed.x > open.x + 0.002:
		print("FAIL sealed rod did not trap air")
		ok = false
	var sprung: Dictionary = _spring_case()
	return ok and sprung["ok"]


func _run_case(seal_ports: bool, load_n: float, action: String, bar: float, seconds: float):
	var circuit = CircuitScript.new()
	var source = circuit.add_element("source", Vector2(40, 120))
	var cylinder = circuit.add_element("cylinder", Vector2(260, 120))
	source.pressure_bar = bar
	cylinder.action = action
	cylinder.load_n = load_n
	cylinder.open_ports = not seal_ports
	cylinder.bore_mm = 32.0
	cylinder.rod_mm = 12.0
	cylinder.stroke_mm = 100.0
	cylinder.mass_kg = 0.25
	cylinder.friction_n = 8.0
	circuit.reconfigure_action(cylinder)
	if not circuit.add_wire(source.id, "out", cylinder.id, "cap"):
		print("FAIL wire")
	var t := 0.0
	while t < seconds:
		circuit.step(0.05)
		t += 0.05
	return cylinder


func _spring_case() -> Dictionary:
	var circuit = CircuitScript.new()
	var source = circuit.add_element("source", Vector2(40, 80))
	var cylinder = circuit.add_element("cylinder", Vector2(240, 80))
	cylinder.action = "spring_return"
	cylinder.spring_rate = 0.8
	cylinder.spring_preload = 25.0
	cylinder.friction_n = 6.0
	cylinder.mass_kg = 0.2
	circuit.reconfigure_action(cylinder)
	source.pressure_bar = 6.0
	circuit.add_wire(source.id, "out", cylinder.id, "cap")
	var t := 0.0
	while t < 2.0:
		circuit.step(0.05)
		t += 0.05
	var extended: float = cylinder.x
	source.pressure_bar = 0.0
	t = 0.0
	while t < 3.0:
		circuit.step(0.05)
		t += 0.05
	var back: float = cylinder.x
	print("spring x_out=%.1f x_back=%.1f" % [extended * 1000.0, back * 1000.0])
	var ok: bool = extended > 0.04 and back < extended * 0.45 and _finite(cylinder)
	if not ok:
		print("FAIL spring return")
	return {"ok": ok, "x": extended, "v": back * 1000.0}


func _check_symbol_and_mesh() -> bool:
	var circuit = CircuitScript.new()
	var cylinder = circuit.add_element("cylinder", Vector2.ZERO)
	if Geom.ports(cylinder).size() != 2:
		print("FAIL double ports")
		return false
	cylinder.action = "spring_return"
	if Geom.ports(cylinder).size() != 1:
		print("FAIL spring ports")
		return false
	var short := Iso.assembly_length_m(32.0, 50.0)
	var long := Iso.assembly_length_m(32.0, 250.0)
	print("length short=%.4f long=%.4f" % [short, long])
	if absf((long - short) - 0.2) > 1.0e-6:
		print("FAIL stroke length")
		return false
	var host := Node3D.new()
	root.add_child(host)
	cylinder.action = "double"
	var info: Dictionary = Iso.build(host, cylinder)
	var count := host.get_child_count()
	var bounds := AABB()
	var has_bounds := false
	var pending: Array = [host]
	while not pending.is_empty():
		var node: Node = pending.pop_back()
		for child in node.get_children():
			pending.append(child)
			if child is VisualInstance3D:
				var visual := child as VisualInstance3D
				var piece := visual.get_aabb()
				bounds = piece if not has_bounds else bounds.merge(piece)
				has_bounds = true
	print("mesh children=%d ports=%s bounds=%s" % [count, info["ports"].keys(), bounds.size])
	host.queue_free()
	return count > 12 and has_bounds and bounds.size.length() > 0.01 and info["ports"].has("cap") and info["ports"].has("rod")


func _check_realism_wave() -> bool:
	var ok := true
	# Волна 1: закрытая игла PPV даёт больший drag в зоне.
	var closed := _cushion_drag_case(0.05)
	var opened := _cushion_drag_case(0.95)
	print("cush closed_drag=%.1f open_drag=%.1f" % [closed, opened])
	if not (closed > opened * 1.5):
		print("FAIL closed PPV needle should drag more")
		ok = false
	# Волна 2: NC-тормоз держит шток при умеренной силе.
	var circuit = CircuitScript.new()
	var cyl = circuit.add_element("cylinder", Vector2.ZERO)
	cyl.bore_mm = 40.0
	cyl.rod_mm = 16.0
	cyl.stroke_mm = 100.0
	cyl.brake = "nc"
	circuit.retune_geometry(cyl)
	cyl.friction_n = 5.0
	cyl.mass_kg = 0.3
	cyl.p_cap = 101325.0 + 1.5e5
	cyl.p_rod = 101325.0
	cyl.x = 0.04
	cyl.v = 0.0
	for _i in 40:
		circuit._integrate_piston(cyl, 0.02)
	print("brake_nc x=%.1f v=%.3f" % [cyl.x * 1000.0, cyl.v])
	if absf(cyl.x - 0.04) > 0.003 or absf(cyl.v) > 0.05:
		print("FAIL NC brake should hold under mild force")
		ok = false
	# Волна 5: утечка сажает давление в запертой полости.
	if not _leak_pressure_case():
		ok = false
	# Волна 6: YSR сильнее elastic у конца хода.
	var soft := _bump_drag_case("elastic")
	var ysr := _bump_drag_case("ysr")
	print("bump elastic_drag=%.1f ysr_drag=%.1f" % [soft, ysr])
	if not (ysr > soft * 1.5):
		print("FAIL YSR bump should drag more than elastic")
		ok = false
	# Каталог: self/PPS + mount + guide не сбрасываются зря.
	cyl.cush_cap = "self"
	cyl.mount = "foot"
	cyl.guide = "bushing"
	cyl.body_style = "compact"
	cyl.body_style_user = true
	var note: String = circuit.retune_geometry(cyl)
	print("catalog cush=%s mount=%s guide=%s body=%s note=%s" % [cyl.cush_cap, cyl.mount, cyl.guide, cyl.body_style, note])
	if cyl.cush_cap != "self" or cyl.mount != "foot" or cyl.guide != "bushing" or cyl.body_style != "compact":
		print("FAIL realism options should persist through conform")
		ok = false
	return ok


func _cushion_drag_case(open_amt: float) -> float:
	var circuit = CircuitScript.new()
	var cyl = circuit.add_element("cylinder", Vector2.ZERO)
	cyl.bore_mm = 32.0
	cyl.rod_mm = 12.0
	cyl.stroke_mm = 100.0
	cyl.cush_rod = "adjustable"
	cyl.cush_open_rod = open_amt
	circuit.retune_geometry(cyl)
	cyl.x = 0.090
	cyl.v = 1.0
	return absf(circuit._cushion_force(cyl, 40.0))


func _bump_drag_case(kind: String) -> float:
	var circuit = CircuitScript.new()
	var cyl = circuit.add_element("cylinder", Vector2.ZERO)
	cyl.bore_mm = 32.0
	cyl.rod_mm = 0.0
	cyl.stroke_mm = 200.0
	cyl.rod_mode = "rodless"
	cyl.carriage = "plain"
	cyl.bump_end = kind
	cyl.cush_cap = "none"
	cyl.cush_rod = "none"
	circuit.retune_geometry(cyl)
	cyl.bump_end = kind
	var zone := 0.004 if kind == "elastic" else 0.012
	cyl.x = 0.200 - zone * 0.5
	cyl.v = 1.0
	return absf(circuit._bump_end_force(cyl, 40.0))


func _leak_pressure_case() -> bool:
	var circuit = CircuitScript.new()
	var cyl = circuit.add_element("cylinder", Vector2.ZERO)
	cyl.bore_mm = 32.0
	cyl.rod_mm = 12.0
	cyl.stroke_mm = 80.0
	cyl.open_ports = false
	cyl.seal_leak = 0.0
	circuit.retune_geometry(cyl)
	cyl.friction_n = 5000.0
	cyl.load_n = 0.0
	cyl.mass_kg = 5.0
	cyl.x = 0.04
	cyl.v = 0.0
	cyl.p_cap = 101325.0 + 5.0e5
	cyl.p_rod = 101325.0
	cyl.m_cap = cyl.p_cap * circuit.chamber_volume(cyl, "cap") / (CircuitScript.R_AIR * circuit.gas_t)
	cyl.m_rod = cyl.p_rod * circuit.chamber_volume(cyl, "rod") / (CircuitScript.R_AIR * circuit.gas_t)
	var p0: float = cyl.p_cap
	var t := 0.0
	while t < 1.5:
		circuit.step(0.05)
		t += 0.05
	var drop_sealed: float = p0 - cyl.p_cap
	cyl.seal_leak = 0.8
	cyl.friction_n = 5000.0
	cyl.x = 0.04
	cyl.v = 0.0
	cyl.p_cap = 101325.0 + 5.0e5
	cyl.p_rod = 101325.0
	cyl.m_cap = cyl.p_cap * circuit.chamber_volume(cyl, "cap") / (CircuitScript.R_AIR * circuit.gas_t)
	cyl.m_rod = cyl.p_rod * circuit.chamber_volume(cyl, "rod") / (CircuitScript.R_AIR * circuit.gas_t)
	p0 = cyl.p_cap
	t = 0.0
	while t < 1.5:
		circuit.step(0.05)
		t += 0.05
	var drop_leak: float = p0 - cyl.p_cap
	print("leak drop_sealed=%.0f drop_leak=%.0f Pa x=%.1f" % [drop_sealed, drop_leak, cyl.x * 1000.0])
	if drop_leak < drop_sealed + 2.0e4:
		print("FAIL seal_leak should drop chamber pressure faster")
		return false
	return true


func _check_valve() -> bool:
	var ValveCat = preload("res://scripts/domain/valve_catalog.gd")
	var IsoV = preload("res://scripts/view3d/iso_valve.gd")
	var circuit = CircuitScript.new()
	var source = circuit.add_element("source", Vector2(40, 40))
	var valve = circuit.add_element("valve", Vector2(180, 40))
	var cylinder = circuit.add_element("cylinder", Vector2(360, 40))
	source.pressure_bar = 6.0
	valve.valve_ways = 5
	valve.valve_positions = 2
	valve.op_left = "solenoid_pilot"
	valve.op_right = "spring"
	circuit.retune_geometry(valve)
	cylinder.bore_mm = 32.0
	cylinder.rod_mm = 12.0
	cylinder.stroke_mm = 80.0
	cylinder.friction_n = 6.0
	cylinder.mass_kg = 0.25
	circuit.retune_geometry(cylinder)
	# Источник → 1(P), 2(A) → cap цилиндра, 4(B) → rod, выхлопы открыты.
	if not circuit.add_wire(source.id, "out", valve.id, "1"):
		print("FAIL valve wire P")
		return false
	if not circuit.add_wire(valve.id, "2", cylinder.id, "cap"):
		print("FAIL valve wire A")
		return false
	if not circuit.add_wire(valve.id, "4", cylinder.id, "rod"):
		print("FAIL valve wire B")
		return false
	# Покой: пружина справа → rest_pos=1 → пути 1-4, 2-3 → давление в rod.
	valve.command_left = false
	var t := 0.0
	while t < 1.2:
		circuit.step(0.05)
		t += 0.05
	print("valve rest pos=%d x=%.1f" % [valve.valve_pos, cylinder.x * 1000.0])
	# Соленоид: pos=0 → 1-2, 4-5 → выдвижение.
	valve.command_left = true
	t = 0.0
	while t < 2.0:
		circuit.step(0.05)
		t += 0.05
	print("valve act pos=%d x=%.1f" % [valve.valve_pos, cylinder.x * 1000.0])
	if valve.valve_pos != 0:
		print("FAIL solenoid should select left position")
		return false
	if cylinder.x < 0.04:
		print("FAIL cylinder should extend through valve")
		return false
	# Матрица 5/3 closed center пустая.
	valve.valve_positions = 3
	valve.valve_center = "closed"
	circuit.retune_geometry(valve)
	var mid: Array = ValveCat.path_pairs(valve, 1)
	if not mid.is_empty():
		print("FAIL closed center should have no paths")
		return false
	# УГО: solenoid_pilot стек; muffler без точки; пилот 12 на гипотенузе.
	valve.valve_positions = 2
	valve.op_left = "solenoid_pilot"
	valve.op_right = "spring"
	valve.port_3 = "muffler"
	valve.port_5 = "muffler"
	circuit.retune_geometry(valve)
	# Рабочие 1/2/4 + пилот 12; глушители 3/5 — без точки.
	if not Geom.port_by_name(valve, "3").is_empty() or not Geom.port_by_name(valve, "5").is_empty():
		print("FAIL muffler exhaust must not expose tube ports")
		return false
	if Geom.port_by_name(valve, "12").is_empty():
		print("FAIL solenoid_pilot needs port 12 on pilot hypotenuse")
		return false
	if Geom.port_by_name(valve, "1").is_empty() or Geom.port_by_name(valve, "2").is_empty():
		print("FAIL valve working ports")
		return false
	for port in Geom.ports(valve):
		var pname := str(port["name"])
		var tip: Vector2 = port["local"]
		var n: Vector2 = port["normal"]
		# 12/14 — только точка на пилоте, без отростка.
		if pname == "12" or pname == "14":
			continue
		var edge: Vector2 = port.get("edge", tip)
		if tip.distance_to(edge) < 8.0:
			print("FAIL valve stub too short %s" % pname)
			return false
		if (tip - edge).dot(n) <= 0.0:
			print("FAIL valve tip not outward %s" % pname)
			return false
	# Якорь портов неподвижен при смене valve_pos.
	var p1_rest: Vector2 = Geom.port_by_name(valve, "1")["local"]
	valve.valve_pos = 0
	var p1_act: Vector2 = Geom.port_by_name(valve, "1")["local"]
	if p1_rest.distance_to(p1_act) > 0.01:
		print("FAIL working ports must stay fixed when valve_pos changes")
		return false
	# 5/3: пилот 12/14 совпадает с органом при ненулевом slide.
	valve.valve_positions = 3
	valve.valve_center = "closed"
	valve.op_left = "solenoid_pilot"
	valve.op_right = "solenoid_pilot"
	circuit.retune_geometry(valve)
	valve.valve_pos = 0
	var p12 = Geom.port_by_name(valve, "12")
	var op_l: Dictionary = Geom.valve_operator_bbox(valve, true)
	if p12.is_empty():
		print("FAIL 5/3 needs pilot 12")
		return false
	var p12x: float = p12["local"].x
	if p12x < float(op_l["left"]) - 0.5 or p12x > float(op_l["right"]) + 0.5:
		print("FAIL pilot 12 outside operator bbox x=%.1f box=%s" % [p12x, op_l])
		return false
	valve.valve_positions = 2
	valve.op_right = "spring"
	circuit.retune_geometry(valve)
	valve.valve_pos = int(valve.rest_pos)
	var sol: Dictionary = Geom.valve_operator_bbox(valve, true)
	var spr: Dictionary = Geom.valve_operator_bbox(valve, false)
	var sol_h := float(sol["bottom"]) - float(sol["top"])
	var sol_w := float(sol["right"]) - float(sol["left"])
	var body_bot := Geom.VALVE_SQ * 0.5
	var want_h := 2.0 * Geom.VALVE_SOL_H
	if absf(sol_h - want_h) > 0.01 or absf(sol_w - Geom.VALVE_SOL_W) > 0.01:
		print("FAIL solenoid_pilot stack want %.1fx%.1f got %.1fx%.1f" % [Geom.VALVE_SOL_W, want_h, sol_w, sol_h])
		return false
	if absf(float(sol["bottom"]) - body_bot) > 0.01:
		print("FAIL coil stack not bottom-aligned %s" % sol)
		return false
	valve.op_left = "solenoid"
	circuit.retune_geometry(valve)
	if not Geom.port_by_name(valve, "12").is_empty():
		print("FAIL plain solenoid must not have port 12")
		return false
	var coil_only: Dictionary = Geom.valve_operator_bbox(valve, true)
	var coil_h := float(coil_only["bottom"]) - float(coil_only["top"])
	if absf(coil_h - Geom.VALVE_SOL_H) > 0.01:
		print("FAIL plain solenoid height")
		return false
	valve.op_left = "solenoid_pilot"
	circuit.retune_geometry(valve)
	var spr_h := float(spr["bottom"]) - float(spr["top"])
	var spr_w := float(spr["right"]) - float(spr["left"])
	if absf(spr_h - Geom.VALVE_SOL_H) > 0.01 or absf(spr_w - Geom.VALVE_SPR_W) > 0.01:
		print("FAIL spring want %.1fx%.1f got %.1fx%.1f" % [Geom.VALVE_SPR_W, Geom.VALVE_SOL_H, spr_w, spr_h])
		return false
	var muff: Dictionary = Geom.valve_muffler_mark_metrics()
	if absf(float(muff["aspect"]) - 2.0) > 0.05 or float(muff["rect_w"]) <= float(muff["rect_h"]):
		print("FAIL muffler must be ~2:1 rect, not square/diamond %s" % muff)
		return false
	print("ugo solenoid_pilot stack %.1fx%.1f muff_no_port spr_w=%.1f" % [sol_w, sol_h, spr_w])
	valve.port_3 = "muffler"
	valve.port_5 = "fitting"
	circuit.retune_geometry(valve)
	if ValveCat.exhaust_fit(valve, "3") != "muffler" or ValveCat.exhaust_fit(valve, "5") != "fitting":
		print("FAIL exhaust_fit options")
		return false
	if not Geom.port_by_name(valve, "3").is_empty() or Geom.port_by_name(valve, "5").is_empty():
		print("FAIL muffler hides port / fitting keeps port")
		return false
	var host := Node3D.new()
	root.add_child(host)
	var info: Dictionary = IsoV.build(host, valve, circuit)
	var kids := host.get_child_count()
	if host.get_node_or_null("SpringR") == null:
		print("FAIL spring node missing")
		host.queue_free()
		return false
	if host.get_node_or_null("Spool") == null:
		print("FAIL spool missing")
		host.queue_free()
		return false
	# Без элемента coil — не должно быть узлов CoilBody/CoilDin.
	if host.get_node_or_null("CoilBody") != null or host.get_node_or_null("CoilDin") != null:
		print("FAIL coil mesh without linked coil element")
		host.queue_free()
		return false
	var gap := IsoV.armature_gap_m(host, true)
	if gap > 0.0025:
		print("FAIL armature gap too large %.4f m" % gap)
		host.queue_free()
		return false
	host.queue_free()
	if kids < 6 or not info["ports"].has("1"):
		print("FAIL valve mesh")
		return false
	# Отдельный элемент coil: УГО с портами проводов A1 (верх) / A2 (низ).
	var coil = circuit.add_element("coil", Vector2(180, 140))
	var coil_ports: Array = Geom.ports(coil)
	if coil_ports.size() != 2:
		print("FAIL coil must have A1/A2 wire ports")
		return false
	var a1 := Geom.port_by_name(coil, "A1")
	var a2 := Geom.port_by_name(coil, "A2")
	if a1.is_empty() or a2.is_empty():
		print("FAIL coil ports A1/A2 missing")
		return false
	if float(a1["local"].y) >= 0.0 or float(a2["local"].y) <= 0.0:
		print("FAIL coil A1 top / A2 bottom %s %s" % [a1, a2])
		return false
	if a1["normal"] != Vector2.UP or a2["normal"] != Vector2.DOWN:
		print("FAIL coil port normals")
		return false
	print("valve mesh children=%d ports=%s gap=%.4f coil_ports=A1/A2" % [kids, info["ports"].keys(), gap])
	return true


func _check_valve_library() -> bool:
	var ValveCat = preload("res://scripts/domain/valve_catalog.gd")
	var ValveLib = preload("res://scripts/domain/valve_library.gd")
	var circuit = CircuitScript.new()
	var valve = circuit.add_element("valve", Vector2(100, 40))
	# Дефолт add_element → рецепт 5/2 sol/spring, пути из библиотеки.
	if str(valve.recipe_id) != "5_2_sol_spring":
		print("FAIL default valve recipe_id")
		return false
	if valve.spool_envelopes.size() != 2:
		print("FAIL default spool_envelopes size")
		return false
	if str(valve.spool_envelopes[0]) != "5_2_work_P_A" or str(valve.spool_envelopes[1]) != "5_2_rest_P_B":
		print("FAIL default spool envelope ids %s" % [valve.spool_envelopes])
		return false
	var left: Array = ValveCat.path_pairs(valve, 0)
	var right: Array = ValveCat.path_pairs(valve, 1)
	if left != [["1", "2"], ["4", "5"]]:
		print("FAIL library 5/2 left paths %s" % [left])
		return false
	if right != [["1", "4"], ["2", "3"]]:
		print("FAIL library 5/2 right paths %s" % [right])
		return false
	# Смена клетки меняет path_pairs.
	valve.spool_envelopes = PackedStringArray(["5_3_center_exhausted", "5_2_rest_P_B"])
	valve.recipe_id = ""
	circuit.retune_geometry(valve)
	var swapped: Array = ValveCat.path_pairs(valve, 0)
	if swapped != [["2", "3"], ["4", "5"]]:
		print("FAIL spool_envelopes[0] override %s" % [swapped])
		return false
	# 5/3 closed center из библиотеки.
	valve.recipe_id = ""
	valve.spool_envelopes = PackedStringArray()
	valve.valve_ways = 5
	valve.valve_positions = 3
	valve.valve_center = "closed"
	circuit.retune_geometry(valve)
	var mid: Array = ValveCat.path_pairs(valve, 1)
	if not mid.is_empty():
		print("FAIL library 5/3 closed center paths %s" % [mid])
		return false
	if str(valve.spool_envelopes[1]) != "5_3_center_closed":
		print("FAIL 5/3 closed envelope id %s" % [valve.spool_envelopes])
		return false
	# Старая схема без recipe/spool → conform подставляет прежние дефолты.
	var legacy = CircuitScript.Element.new()
	legacy.kind = "valve"
	legacy.valve_ways = 5
	legacy.valve_positions = 2
	legacy.op_left = "solenoid_pilot"
	legacy.op_right = "spring"
	legacy.port_3 = "muffler"
	legacy.port_5 = "muffler"
	ValveCat.conform(legacy)
	if legacy.spool_envelopes.size() != 2:
		print("FAIL legacy conform spool size")
		return false
	var leg_left: Array = ValveCat.path_pairs(legacy, 0)
	var leg_right: Array = ValveCat.path_pairs(legacy, 1)
	if leg_left != [["1", "2"], ["4", "5"]] or leg_right != [["1", "4"], ["2", "3"]]:
		print("FAIL legacy defaults paths L=%s R=%s" % [leg_left, leg_right])
		return false
	if ValveLib.envelope("5_2_work_P_A").is_empty() or ValveLib.recipe("5_2_sol_spring").is_empty():
		print("FAIL ValveLibrary JSON load")
		return false
	print("valve_library ok envelopes=%d recipes=%d" % [
		ValveLib.envelopes_for_ways(5).size(), ValveLib.all_recipes().size()
	])
	return true


func _check_accessories() -> bool:
	var AccLib = preload("res://scripts/domain/accessory_library.gd")
	if AccLib.recipe("throttle").is_empty() or AccLib.recipe("throttle_fixed").is_empty() \
			or AccLib.all_recipes().size() < 7:
		print("FAIL accessory recipes load")
		return false
	var circuit = CircuitScript.new()
	var src = circuit.add_element("source", Vector2(40, 40))
	src.pressure_bar = 6.0
	var thr = circuit.add_element("accessory@throttle", Vector2(140, 40))
	thr.opening = 0.15
	var chk = circuit.add_element("accessory@check", Vector2(240, 40))
	var cyl = circuit.add_element("cylinder@da_basic", Vector2(340, 40))
	if str(thr.kind) != "accessory" or str(thr.accessory_class) != "throttle":
		print("FAIL accessory kind/class")
		return false
	if Geom.ports(thr).size() != 2:
		print("FAIL accessory ports")
		return false
	circuit.add_wire(src.id, "out", thr.id, "1")
	circuit.add_wire(thr.id, "2", chk.id, "1")
	circuit.add_wire(chk.id, "2", cyl.id, "cap")
	circuit.running = true
	for _i in 80:
		circuit.step(0.02)
	var x_throttled: float = float(cyl.x)
	# Шире открытый дроссель — быстрее ход.
	circuit.clear_scene()
	src = circuit.add_element("source", Vector2(40, 40))
	src.pressure_bar = 6.0
	thr = circuit.add_element("accessory@throttle", Vector2(140, 40))
	thr.opening = 1.0
	chk = circuit.add_element("accessory@check", Vector2(240, 40))
	cyl = circuit.add_element("cylinder@da_basic", Vector2(340, 40))
	circuit.add_wire(src.id, "out", thr.id, "1")
	circuit.add_wire(thr.id, "2", chk.id, "1")
	circuit.add_wire(chk.id, "2", cyl.id, "cap")
	circuit.running = true
	for _j in 80:
		circuit.step(0.02)
	var x_open: float = float(cyl.x)
	if x_open <= x_throttled + 0.002:
		print("FAIL throttle opening effect open=%.4f throttled=%.4f" % [x_open, x_throttled])
		return false
	# Ресивер копит давление.
	circuit.clear_scene()
	src = circuit.add_element("source", Vector2(40, 40))
	src.pressure_bar = 5.0
	var res = circuit.add_element("accessory@reservoir", Vector2(140, 40))
	res.volume_l = 0.25
	circuit.add_wire(src.id, "out", res.id, "1")
	circuit.running = true
	for _k in 120:
		circuit.step(0.02)
	var p_res: float = float(res.port_press.get("1", 101325.0))
	if p_res < 2.5e5:
		print("FAIL reservoir charge p=%.0f" % p_res)
		return false
	print("accessories ok recipes=%d throttle_dx=%.3f reservoir_p=%.2fbar" % [
		AccLib.all_recipes().size(), x_open - x_throttled, (p_res - 101325.0) / 1.0e5
	])
	return true


func _check_valve_nc_blocks() -> bool:
	# Источник → 3/2 NC (покой) → цилиндр: шток не должен выезжать без команды.
	var circuit = CircuitScript.new()
	var src = circuit.add_element("source", Vector2(40, 40))
	src.pressure_bar = 6.0
	var valve = circuit.add_element("valve@3_2_nc_button_spring", Vector2(180, 40))
	var cyl = circuit.add_element("cylinder@da_basic", Vector2(340, 40))
	cyl.stroke_mm = 80.0
	cyl.friction_n = 6.0
	cyl.mass_kg = 0.25
	circuit.retune_geometry(cyl)
	if not SceneBuilder.must_wire(circuit, src.id, "out", valve.id, "1", "P"):
		print("FAIL nc wire P")
		return false
	if not SceneBuilder.must_wire(circuit, valve.id, "2", cyl.id, "cap", "A"):
		print("FAIL nc wire A")
		return false
	if not SceneBuilder.assert_topology(circuit, "nc_block"):
		return false
	valve.command_left = false
	circuit.running = true
	for _i in 60:
		circuit.step(0.05)
	var x_rest: float = float(cyl.x)
	if x_rest > 0.008:
		print("FAIL 3/2 NC rest should block extend x=%.4f" % x_rest)
		return false
	valve.command_left = true
	for _j in 80:
		circuit.step(0.05)
	var x_act: float = float(cyl.x)
	if x_act < 0.03:
		print("FAIL 3/2 NC actuated should extend x=%.4f" % x_act)
		return false
	print("nc_block ok rest=%.4f act=%.4f" % [x_rest, x_act])
	return true


func _check_lamp_needs_return() -> bool:
	# Только фаза на X1 без нейтрали — лампа не горит.
	var circuit = CircuitScript.new()
	var supply = circuit.add_element("electro@supply_1ph", Vector2(40, 40))
	var lamp = circuit.add_element("electro@lamp", Vector2(200, 40))
	if supply == null or lamp == null:
		print("FAIL lamp elements")
		return false
	if str(supply.electro_class) != "supply" or str(lamp.electro_class) != "lamp":
		print("FAIL lamp recipes supply=%s lamp=%s" % [supply.electro_class, lamp.electro_class])
		return false
	var ep_l = ElectroLib.supply_endpoint_for_port(circuit, supply, "L")
	var ep_n = ElectroLib.supply_endpoint_for_port(circuit, supply, "N")
	if ep_l == null or ep_n == null:
		print("FAIL supply endpoints L/N")
		return false
	if not SceneBuilder.must_wire(circuit, int(ep_l.id), "L", lamp.id, "X1", "L-only"):
		print("FAIL lamp L wire")
		return false
	if not SceneBuilder.assert_topology(circuit, "lamp_open"):
		return false
	circuit.running = true
	for _i in 10:
		circuit.step(0.05)
	if bool(lamp.lit):
		print("FAIL lamp must stay off without N")
		return false
	# Замкнуть на N — должна загореться.
	if not SceneBuilder.must_wire(circuit, int(ep_n.id), "N", lamp.id, "X2", "N"):
		print("FAIL lamp N wire")
		return false
	for _j in 10:
		circuit.step(0.05)
	if not bool(lamp.lit):
		print("FAIL lamp should light with L and N")
		return false
	print("lamp_return ok")
	return true


func _check_electro_sim_topology() -> bool:
	var dir := "res://test/electro_sim"
	var da := DirAccess.open(dir)
	if da == null:
		print("FAIL electro_sim dir missing")
		return false
	var ok := true
	var n := 0
	da.list_dir_begin()
	var name := da.get_next()
	while name != "":
		if not da.current_is_dir() and name.ends_with(".mechsim.json"):
			n += 1
			var path := "%s/%s" % [dir, name]
			var res: Dictionary = SceneBuilder.load_and_validate(path)
			if not bool(res.get("ok", false)):
				ok = false
				print("FAIL topology %s" % name)
				for err in res.get("errors", PackedStringArray()):
					print("  %s" % str(err))
		name = da.get_next()
	da.list_dir_end()
	if n < 1:
		print("FAIL no electro_sim scenes")
		return false
	if ok:
		print("electro_sim topology ok files=%d" % n)
	return ok


## Локальные tip портов электроУГО — на узлах SCH_GRID (провода не «ломаются» у вывода).
func _check_electro_ports_on_grid() -> bool:
	var ElectroSym = preload("res://scripts/domain/electro_symbols.gd")
	var circuit = CircuitScript.new()
	var kinds: Array = [
		"electro@psu_24",
		"electro@supply_1ph",
		"electro@term_block_4",
		"electro@lamp",
		"electro@mcb_1p",
	]
	for kind in kinds:
		var el = circuit.add_element(kind, Vector2(100, 100))
		if el == null:
			print("FAIL ports_grid add %s" % kind)
			return false
		var ports: Array = ElectroSym.ports(el)
		if ports.is_empty() and str(el.electro_class) != "din_stop":
			print("FAIL ports_grid empty %s" % kind)
			return false
		for p in ports:
			if typeof(p) != TYPE_DICTIONARY:
				continue
			var loc: Vector2 = p["local"] as Vector2
			var ox: float = absf(loc.x / Geom.SCH_GRID - roundf(loc.x / Geom.SCH_GRID))
			var oy: float = absf(loc.y / Geom.SCH_GRID - roundf(loc.y / Geom.SCH_GRID))
			if ox > 1.0e-3 or oy > 1.0e-3:
				print("FAIL ports_grid %s %s at (%.2f, %.2f)" % [kind, str(p.get("name", "?")), loc.x, loc.y])
				return false
	print("electro_ports_on_grid ok")
	return true


func _check_rail_and_layout() -> bool:
	var circuit = CircuitScript.new()
	var supply = circuit.add_element("electro@supply_1ph", Vector2(40, 40))
	var lamp_a = circuit.add_element("electro@lamp", Vector2(200, 40))
	var lamp_b = circuit.add_element("electro@lamp", Vector2(320, 40))
	var rail = circuit.add_element("rail@electric", Vector2(140, 100))
	if supply == null or lamp_a == null or lamp_b == null or rail == null:
		print("FAIL rail elements")
		return false
	if str(rail.kind) != "rail" or str(rail.rail_domain) != "electric":
		print("FAIL rail kind/domain")
		return false
	if not Geom.ports(rail).is_empty():
		print("FAIL rail must have no ports")
		return false
	var ep_l2 = ElectroLib.supply_endpoint_for_port(circuit, supply, "L")
	var ep_n2 = ElectroLib.supply_endpoint_for_port(circuit, supply, "N")
	if ep_l2 == null or ep_n2 == null:
		print("FAIL supply endpoints for rail test")
		return false
	if circuit.connect_to_rail(int(ep_l2.id), "L", rail.id, Geom.to_world(rail, Vector2.ZERO)):
		print("FAIL connect_to_rail must be rejected")
		return false
	if circuit.add_wire(int(ep_l2.id), "L", rail.id, "t1"):
		print("FAIL add_wire to rail must fail")
		return false
	# Прямые связи приборов; шина только перекрывает общий участок трассы.
	if not SceneBuilder.must_wire(circuit, int(ep_l2.id), "L", lamp_a.id, "X1", "L1"):
		return false
	if not SceneBuilder.must_wire(circuit, lamp_a.id, "X2", lamp_b.id, "X1", "bridge"):
		return false
	if not SceneBuilder.must_wire(circuit, int(ep_n2.id), "N", lamp_b.id, "X2", "N"):
		return false
	Rail2D.ensure_points(rail)
	rail.rail_points = PackedVector2Array([Vector2(-80, 0), Vector2(80, 0)])
	rail.position = Vector2(180, 100)
	var WireRouter2D = preload("res://scripts/domain/wire_router_2d.gd")
	WireRouter2D.invalidate()
	var w0 = circuit.wires[0]
	var full: PackedVector2Array = WireRouter2D.path_for(circuit, w0)
	# Коридор только при ⊥ входе/выходе (не вдоль шины и не nearest-притяжение).
	var forced := PackedVector2Array([
		Vector2(100, 40),
		Vector2(100, 100),
		Vector2(260, 100),
		Vector2(260, 40),
	])
	var vis: Dictionary = Rail2D.visual_for_path(circuit, "electric", forced)
	var parts: Array = vis.get("parts", []) as Array
	var gates: Array = vis.get("gates", []) as Array
	if parts.size() < 2 or gates.size() < 2:
		print("FAIL rail visual clip parts=%d gates=%d" % [parts.size(), gates.size()])
		return false
	var pa: PackedVector2Array = parts[0] as PackedVector2Array
	var pb: PackedVector2Array = parts[1] as PackedVector2Array
	if not Rail2D.point_near_rail(circuit, "electric", pa[pa.size() - 1], 1.0):
		print("FAIL part_a must end on rail")
		return false
	if not Rail2D.point_near_rail(circuit, "electric", pb[0], 1.0):
		print("FAIL part_b must start on rail")
		return false
	if pa[pa.size() - 1].x > pb[0].x + 1.0:
		print("FAIL part_a end past part_b start")
		return false
	# Вход/выход — точки ⊥-пересечения, не проекции tip.
	if pa[pa.size() - 1].distance_to(Vector2(100, 100)) > 1.0:
		print("FAIL enter not at perp gate")
		return false
	if pb[0].distance_to(Vector2(260, 100)) > 1.0:
		print("FAIL exit not at perp gate")
		return false
	# Вдоль шины без ⊥ — коридора нет.
	var along_only := PackedVector2Array([Vector2(100, 100), Vector2(260, 100)])
	var vis_along: Dictionary = Rail2D.visual_for_path(circuit, "electric", along_only)
	var parts_along: Array = vis_along.get("parts", []) as Array
	if parts_along.size() >= 2:
		print("FAIL along-rail must not merge")
		return false
	var n_wires: int = circuit.wires.size()
	circuit.remove_element(rail.id)
	if circuit.wires.size() != n_wires:
		print("FAIL deleting visual rail must keep wires")
		return false
	# Вертикальная шина: ⊥ вход сверху и выход вправо.
	var rail_v = circuit.add_element("rail@electric", Vector2(100, 100))
	rail_v.rail_points = PackedVector2Array([Vector2(0, -60), Vector2(0, 60)])
	var forced_v := PackedVector2Array([
		Vector2(0, 50),
		Vector2(100, 50),
		Vector2(100, 150),
		Vector2(200, 150),
	])
	var vis_v: Dictionary = Rail2D.visual_for_path(circuit, "electric", forced_v)
	var parts_v: Array = vis_v.get("parts", []) as Array
	if parts_v.size() < 2:
		print("FAIL vertical rail clip parts=%d" % parts_v.size())
		return false
	var pav: PackedVector2Array = parts_v[0] as PackedVector2Array
	if pav[pav.size() - 1].distance_to(Vector2(100, 50)) > 1.0:
		print("FAIL vertical clip stub=%s" % str(pav[pav.size() - 1]))
		return false
	circuit.remove_element(rail_v.id)
	var lay: Dictionary = SchematicLayout.arrange(circuit)
	if not bool(lay.get("ok", false)):
		print("FAIL layout arrange")
		return false
	if not SceneBuilder.assert_topology(circuit, "rail_visual"):
		return false
	print("rail_visual ok parts=%d gates=%d" % [parts.size(), gates.size()])
	return true

func _bar(p: float) -> float:
	return (p - 101325.0) / 1.0e5


func _finite(el) -> bool:
	return is_finite(el.x) and is_finite(el.v) and is_finite(el.p_cap) and is_finite(el.p_rod)
