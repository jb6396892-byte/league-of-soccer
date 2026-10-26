extends Node3D

const S = preload("res://scripts/shapes.gd")
const RADIUS := 0.34
var velocity := Vector3.ZERO
var visuals_enabled := true
var visual: Node3D
var shadow: MeshInstance3D
var trail: Array[MeshInstance3D] = []
var trail_points: Array[Vector3] = []


func _ready() -> void:
	if not visuals_enabled:
		return
	visual = Node3D.new()
	add_child(visual)
	var white := S.material(Color("#fff9df"), true)
	var black := S.material(Color("#142324"), true)
	S.sphere(visual, Vector3.ZERO, RADIUS, white)
	var directions := [Vector3.UP, Vector3.DOWN]
	for i in range(5):
		var angle := i * TAU / 5.0
		directions.append(Vector3(cos(angle) * 0.894, 0.447, sin(angle) * 0.894))
		directions.append(Vector3(cos(angle + PI / 5) * 0.894, -0.447, sin(angle + PI / 5) * 0.894))
	for direction in directions:
		var patch := CylinderMesh.new()
		patch.top_radius = 0.135
		patch.bottom_radius = 0.135
		patch.height = 0.016
		patch.radial_segments = 5
		var item := S.mesh(visual, patch, direction * 0.315, black)
		item.quaternion = Quaternion(Vector3.UP, direction)
	shadow = S.sphere(get_parent(), Vector3.ZERO, 0.36, S.material(Color("#28583f")))
	shadow.scale.y = 0.025
	var trail_mat := S.material(Color("#cee4a4"), true)
	for i in range(6):
		var dot := S.sphere(get_parent(), Vector3.ZERO, 0.12 - i * 0.013, trail_mat)
		dot.visible = false
		trail.append(dot)


func step(delta: float) -> void:
	velocity.y -= 15.0 * delta
	position += velocity * delta
	if position.y < RADIUS:
		position.y = RADIUS
		velocity.y = -velocity.y * 0.48 if velocity.y < -1.2 else 0.0
		var flat := Vector2(velocity.x, velocity.z).move_toward(Vector2.ZERO, 5.0 * delta)
		velocity.x = flat.x
		velocity.z = flat.y
	velocity.x *= 1.0 - delta * 0.12
	velocity.z *= 1.0 - delta * 0.12
	update_visual(delta)


func update_visual(delta: float) -> void:
	if not visuals_enabled:
		return
	var flat_velocity := Vector3(velocity.x, 0, velocity.z)
	if flat_velocity.length() > 0.1:
		visual.rotate(flat_velocity.normalized().cross(Vector3.UP), -flat_velocity.length() * delta / RADIUS)
	shadow.position = Vector3(position.x, 0.035, position.z)
	shadow.scale.x = 1.0 + position.y * 0.15
	shadow.scale.z = shadow.scale.x
	trail_points.push_front(position)
	if trail_points.size() > 18:
		trail_points.pop_back()
	for i in range(trail.size()):
		trail[i].visible = flat_velocity.length() > 14.0 and trail_points.size() > i * 3
		if trail[i].visible:
			trail[i].position = trail_points[i * 3]
