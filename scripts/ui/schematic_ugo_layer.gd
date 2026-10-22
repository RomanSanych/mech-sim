extends Node2D
## Запечённые УГО как Sprite2D. Drag = смена position, без полного Geom._draw схемы.

const BakerScript = preload("res://scripts/ui/schematic_ugo_baker.gd")
const ElectroLib = preload("res://scripts/domain/electro_library.gd")

var owner_view: Control = null
var _baker: Node = null
var _sprites: Dictionary = {} # id -> Sprite2D
var _origins: Dictionary = {} # id -> local_origin Vector2
var _sigs: Dictionary = {} # id -> bake signature
var _omit_motion: bool = true


func _ready() -> void:
	_baker = BakerScript.new()
	_baker.name = "UgoBaker"
	add_child(_baker)
	_baker.baked.connect(_on_baked)


func set_omit_motion(on: bool) -> void:
	if _omit_motion == on:
		return
	_omit_motion = on
	invalidate_all()


func invalidate_all() -> void:
	_sigs.clear()
	if _baker != null and _baker.has_method("invalidate"):
		_baker.invalidate(-1)


func invalidate_el(el_id: int) -> void:
	_sigs.erase(el_id)
	if _baker != null and _baker.has_method("invalidate"):
		_baker.invalidate(el_id)


func sync(circuit, font: Font, active: bool) -> void:
	visible = active
	if not active or circuit == null or font == null:
		return
	var keep: Dictionary = {}
	for el in circuit.elements:
		if el == null:
			continue
		if ElectroLib.hidden_on_scheme(el) or ElectroLib.coil_contact_hidden_on_scheme(circuit, el):
			continue
		var eid: int = int(el.id)
		keep[eid] = true
		var spr: Sprite2D = _sprites.get(eid) as Sprite2D
		if spr == null:
			spr = Sprite2D.new()
			spr.name = "Ugo_%d" % eid
			spr.centered = false
			spr.z_index = 0
			add_child(spr)
			_sprites[eid] = spr
		var origin: Vector2 = _origins.get(eid, Vector2.ZERO) as Vector2
		spr.position = el.position + origin
		spr.visible = true
		var sig: String = _bake_sig(el)
		if str(_sigs.get(eid, "")) != sig:
			_sigs[eid] = sig
			if _baker != null and _baker.has_method("request_bake"):
				_baker.request_bake(el, font, _omit_motion)
	var drop: Array = []
	for eid2 in _sprites.keys():
		if not keep.has(int(eid2)):
			drop.append(int(eid2))
	for eid3 in drop:
		var s2: Sprite2D = _sprites[eid3] as Sprite2D
		_sprites.erase(eid3)
		_origins.erase(eid3)
		_sigs.erase(eid3)
		if s2 != null:
			s2.queue_free()


func sync_positions(circuit) -> void:
	## Только позиции (drag) — без rebake.
	if circuit == null:
		return
	for el in circuit.elements:
		if el == null:
			continue
		var eid: int = int(el.id)
		var spr: Sprite2D = _sprites.get(eid) as Sprite2D
		if spr == null:
			continue
		var origin: Vector2 = _origins.get(eid, Vector2.ZERO) as Vector2
		spr.position = el.position + origin


func has_texture(el_id: int) -> bool:
	var spr: Sprite2D = _sprites.get(el_id) as Sprite2D
	return spr != null and spr.texture != null


func _bake_sig(el) -> String:
	# Рецепт/поворот/класс — при смене перезапечь. Не x/v (ход — Anim).
	# geom_ver: bump при смене штрихов УГО (иначе спрайт залипает на старом bake).
	var geom_ver: String = "1"
	if str(el.kind) == "air_motor":
		geom_ver = "am5"
	# closed/pressed/lit — иначе АВ/лампа залипают на старом спрайте.
	var dyn: String = ""
	if str(el.kind) == "electro":
		dyn = "c%d|p%d|l%d" % [
			1 if bool(el.closed) else 0,
			1 if bool(el.pressed) else 0,
			1 if bool(el.lit) else 0,
		]
	return "%s|%d|%s|%s|%s|%s|%s|%.1f|%.1f|%s|%s|%s" % [
		str(el.kind),
		int(el.rotation_quad),
		str(el.get("recipe_id")),
		str(el.get("accessory_class")),
		str(el.get("electro_class")),
		str(el.get("junction_style")),
		str(el.tag),
		float(el.tube_od_mm) if el.get("tube_od_mm") != null else 0.0,
		float(el.tube_od_b_mm) if el.get("tube_od_b_mm") != null else 0.0,
		"1" if _omit_motion else "0",
		geom_ver,
		dyn,
	]


func _on_baked(el_id: int, texture: Texture2D, local_origin: Vector2) -> void:
	var spr: Sprite2D = _sprites.get(el_id) as Sprite2D
	if spr == null or texture == null:
		return
	_origins[el_id] = local_origin
	spr.texture = texture
	if owner_view != null and owner_view.get("circuit") != null:
		var el = owner_view.circuit.get_element(el_id)
		if el != null:
			spr.position = el.position + local_origin
