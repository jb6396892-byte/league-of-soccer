extends SubViewport
## A live view of the actual pitch and kit, with no imported promotional artwork.
const Stadium = preload("res://scripts/stadium.gd")
const Footballer = preload("res://scripts/footballer.gd")
const Ball = preload("res://scripts/ball.gd")
const Presentation = preload("res://scripts/match_presentation.gd")
var athlete: Node3D
var active := true
var elapsed := 0.0

func _ready() -> void:
	size = Vector2i(1440, 900)
	own_world_3d = true
	msaa_3d = Viewport.MSAA_2X
	render_target_update_mode = SubViewport.UPDATE_ALWAYS
	var scene := Node3D.new()
	add_child(scene)
	Presentation.light_world(scene)
	scene.add_child(Stadium.new())
	athlete = Footballer.new()
	athlete.shirt_number = 10
	athlete.archetype = 0
	scene.add_child(athlete)
	athlete.position = Vector3(0, 0, -18)
	athlete.facing = Vector3(0.3, 0, -1).normalized()
	athlete.selection.hide()
	athlete.direction_marker.hide()
	var ball := Ball.new()
	scene.add_child(ball)
	ball.position = Vector3(0.9, Ball.RADIUS, -18.7)
	ball.update_visual(0.0)
	var camera := Camera3D.new()
	scene.add_child(camera)
	camera.position = Vector3(4.6, 2.5, -24)
	camera.look_at(Vector3(3.0, 1.2, -17.8))
	camera.fov = 44
	camera.current = true

func _process(delta: float) -> void:
	if not active:
		return
	elapsed += delta
	athlete.animate(delta)
	athlete.body.rotation.z = sin(elapsed * 1.1) * 0.008
	athlete.left_arm.rotation.x = -0.07 + sin(elapsed * 0.8) * 0.025
	athlete.right_arm.rotation.x = 0.05
