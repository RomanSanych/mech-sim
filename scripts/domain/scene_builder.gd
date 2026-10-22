class_name SceneBuilder
extends RefCounted
## Сборка учебных схем только через API редактора (add_element / add_wire).
## Валидация топологии: лимит проводов на порт как в Circuit.port_wire_limit.


static func validate_topology(circuit) -> Dictionary:
	## { "ok": bool, "errors": PackedStringArray }
	var errors: PackedStringArray = PackedStringArray()
	if circuit == null:
		errors.append("circuit is null")
		return {"ok": false, "errors": errors}
	var counts: Dictionary = {} # "el_id:port" -> int
	for wire in circuit.wires:
		var ends: Array = [
			[int(wire.a_id), str(wire.a_port)],
			[int(wire.b_id), str(wire.b_port)],
		]
		for end in ends:
			var eid: int = int(end[0])
			var port: String = str(end[1])
			var key := "%d:%s" % [eid, port]
			counts[key] = int(counts.get(key, 0)) + 1
			var el = circuit.get_element(eid)
			if el == null:
				errors.append("wire %d → missing element %d" % [int(wire.id), eid])
				continue
			var lim: int = int(circuit.port_wire_limit(el, port))
			var n: int = int(counts[key])
			if n > lim:
				errors.append("port %s.%s has %d wires (limit %d)" % [str(el.tag), port, n, lim])
	return {"ok": errors.is_empty(), "errors": errors}


static func must_wire(circuit, a_id: int, a_port: String, b_id: int, b_port: String, label: String = "") -> bool:
	if circuit == null:
		return false
	if circuit.add_wire(a_id, a_port, b_id, b_port):
		return true
	var tag := label if label != "" else "%d.%s→%d.%s" % [a_id, a_port, b_id, b_port]
	push_error("SceneBuilder: add_wire failed: %s" % tag)
	return false


static func assert_topology(circuit, label: String = "") -> bool:
	var res: Dictionary = validate_topology(circuit)
	if bool(res.get("ok", false)):
		return true
	var prefix := label if label != "" else "topology"
	for err in res.get("errors", PackedStringArray()):
		print("FAIL %s: %s" % [prefix, str(err)])
	return false


static func load_and_validate(path: String) -> Dictionary:
	## Загрузить .mechsim.json и проверить топологию.
	## { "ok", "errors", "circuit" }
	var CircuitScript = load("res://scripts/domain/circuit.gd")
	var circuit = CircuitScript.new()
	var loaded: Dictionary = circuit.load_scene_file(path)
	var load_err: String = str(loaded.get("error", ""))
	if load_err != "":
		return {"ok": false, "errors": PackedStringArray([load_err]), "circuit": null}
	var topo: Dictionary = validate_topology(circuit)
	return {"ok": bool(topo.get("ok", false)), "errors": topo.get("errors", PackedStringArray()), "circuit": circuit}
