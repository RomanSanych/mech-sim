class_name CsgBake
extends RefCounted
## CSG → MeshInstance3D.
## Документация Godot 4: mesh CSG обновляется с задержкой в 1 кадр.
## Всегда ждём process_frame, затем `_update_shape` + `bake_static_mesh()`.

static func box(size: Vector3, center: Vector3, op: CSGShape3D.Operation = CSGShape3D.OPERATION_UNION) -> CSGBox3D:
	var n := CSGBox3D.new()
	n.size = size
	n.position = center
	n.operation = op
	return n


static func cyl(
	radius: float, height: float, center: Vector3, axis: String,
	op: CSGShape3D.Operation = CSGShape3D.OPERATION_UNION, sides: int = 24
) -> CSGCylinder3D:
	var n := CSGCylinder3D.new()
	n.radius = radius
	n.height = height
	n.sides = sides
	n.cone = false
	n.operation = op
	n.position = center
	# CSGCylinder3D по умолчанию вдоль +Y (как CylinderMesh / Parts._orient).
	match axis:
		"x":
			n.rotation_degrees = Vector3(0.0, 0.0, 90.0)
		"z":
			n.rotation_degrees = Vector3(90.0, 0.0, 0.0)
		_:
			n.rotation_degrees = Vector3.ZERO
	return n


## Собирает CSG в дереве, запекает в MeshInstance, удаляет CSG.
## Нормали: CSGShape3D.autosmooth + smoothing_angle (дока Godot 4.7).
## Не пересчитывать через SurfaceTool.generate_normals() — это зализывает рёбра.
static func attach(
	parent: Node, combiner: CSGCombiner3D, mat: Material, role: String,
	thermal_part: String = ""
) -> Node3D:
	combiner.name = "CSG_%s" % role
	combiner.material_override = mat
	# Кривые грани сглаживаются, острые (шлиц, торцы) остаются hard-edge.
	combiner.autosmooth = true
	combiner.smoothing_angle = 40.0
	combiner.set_meta("xray_role", role)
	combiner.set_meta("_csg_bake_mat", mat)
	combiner.set_meta("_csg_bake_role", role)
	combiner.set_meta("_csg_bake_tries", 0)
	if thermal_part != "":
		combiner.set_meta("thermal_part", thermal_part)
	combiner.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Сырой CSG скрыт — hover только по MeshInstance3D после bake.
	combiner.visible = false
	parent.add_child(combiner)
	_schedule_bake(parent, combiner)
	return combiner


static func _schedule_bake(parent: Node, combiner: CSGCombiner3D) -> void:
	if parent == null or not is_instance_valid(parent) or not parent.is_inside_tree():
		return
	var tree: SceneTree = parent.get_tree()
	if tree == null:
		return
	# Отдельный timer на каждый combiner: несколько process_frame.connect
	# одного static-callable с разными bind → «already connected».
	var timer: SceneTreeTimer = tree.create_timer(0.0)
	timer.timeout.connect(_on_frame_bake.bind(parent, combiner), CONNECT_ONE_SHOT)


static func _on_frame_bake(parent: Node, combiner: CSGCombiner3D) -> void:
	if not is_instance_valid(combiner) or not is_instance_valid(parent):
		return
	if combiner.get_parent() != parent:
		return
	var mat: Material = combiner.get_meta("_csg_bake_mat", combiner.material_override) as Material
	var role: String = str(combiner.get_meta("_csg_bake_role", "shell"))
	var mi: MeshInstance3D = _bake_to_mi(parent, combiner, mat, role)
	if mi != null:
		return
	var tries: int = int(combiner.get_meta("_csg_bake_tries", 0)) + 1
	combiner.set_meta("_csg_bake_tries", tries)
	if tries < 4:
		_schedule_bake(parent, combiner)
	else:
		combiner.visible = true


static func _bake_to_mi(parent: Node, combiner: CSGCombiner3D, mat: Material, role: String) -> MeshInstance3D:
	# CSG считает геометрию только для видимых root-shape — кратко включаем.
	combiner.visible = true
	if combiner.has_method("_update_shape"):
		combiner.call("_update_shape")
	var baked: ArrayMesh = null
	if combiner.has_method("bake_static_mesh"):
		baked = combiner.bake_static_mesh() as ArrayMesh
	if baked == null or baked.get_surface_count() < 1:
		var packed: Array = combiner.get_meshes()
		if packed.size() >= 2 and packed[1] is Mesh:
			var src: Mesh = packed[1] as Mesh
			if src.get_surface_count() > 0:
				baked = src as ArrayMesh
				if baked == null:
					baked = ArrayMesh.new()
					for si in src.get_surface_count():
						baked.add_surface_from_arrays(
							src.surface_get_primitive_type(si),
							src.surface_get_arrays(si)
						)
	if baked == null or baked.get_surface_count() < 1:
		combiner.visible = false
		return null
	# Нормали уже от CSG (autosmooth). Не вызывать generate_normals().
	var mi := MeshInstance3D.new()
	mi.name = "Mesh_%s" % role
	mi.mesh = baked
	mi.material_override = mat
	mi.set_meta("xray_role", role)
	if combiner.has_meta("thermal_part"):
		mi.set_meta("thermal_part", str(combiner.get_meta("thermal_part")))
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# bake_static_mesh — в локали combiner; сдвиг/поворот узла иначе теряются.
	mi.transform = combiner.transform
	# Имя исходного combiner (BarrelCSG / CapCSG_…) — для тепловизора по частям.
	var cnm: String = str(combiner.name)
	if cnm != "" and not cnm.begins_with("CSG_"):
		mi.name = cnm
	parent.add_child(mi)
	combiner.free()
	# Bake после apply_xray — сбросить флаг, чтобы workshop снова наложил ghost.
	if parent is Node and (parent as Node).has_meta("xray_ok"):
		(parent as Node).remove_meta("xray_ok")
	return mi
