extends Node3D
## Быстрый боковой вид KL (Finder) для проверки лестницы и торца модуля.


class PreviewEl:
	var kind := "electro"
	var electro_class := "relay"
	var electro_mount := "din"
	var recipe_id := "relay_4c"
	var energized := false
	var state := 0
	var tag := "KL1"


func _ready() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.55, 0.57, 0.6)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.8, 0.82, 0.85)
	e.ambient_light_energy = 0.7
	env.environment = e
	add_child(env)

	var key := DirectionalLight3D.new()
	key.light_energy = 1.25
	key.rotation_degrees = Vector3(-35, 40, 0)
	add_child(key)
	var fill := DirectionalLight3D.new()
	fill.light_energy = 0.5
	fill.rotation_degrees = Vector3(20, -120, 0)
	add_child(fill)

	var model := Node3D.new()
	model.name = "Relay"
	add_child(model)
	IsoElectro.build(model, PreviewEl.new())

	var rail := MeshInstance3D.new()
	var rm := BoxMesh.new()
	rm.size = Vector3(0.08, 0.0075, 0.001)
	rail.mesh = rm
	rail.position = Vector3(0, -0.002, -0.042)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.45, 0.47, 0.5)
	rail.material_override = mat
	add_child(rail)

	var cam := Camera3D.new()
	cam.current = true
	cam.fov = 28.0
	cam.near = 0.01
	cam.far = 5.0
	# Смотрим вдоль +X (боковой вид): лестница и торец модуля к +Z.
	cam.position = Vector3(0.15, 0.008, 0.012)
	add_child(cam)
	cam.look_at(Vector3(0, 0.002, 0.008), Vector3.UP)
