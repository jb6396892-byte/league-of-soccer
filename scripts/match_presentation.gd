extends RefCounted
## Shared night-match lighting for the stadium and the menu's live preview.
static func light_world(parent: Node3D) -> void:
	var world := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("#080d17")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("#b4c6e0")
	environment.ambient_light_energy = 0.40
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	world.environment = environment
	parent.add_child(world)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-66, -34, 0)
	key.light_color = Color("#f5f8ff")
	key.light_energy = 1.10
	key.shadow_enabled = true
	key.directional_shadow_max_distance = 160
	parent.add_child(key)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-38, 145, 0)
	fill.light_color = Color("#9fbce7")
	fill.light_energy = 0.32
	parent.add_child(fill)
