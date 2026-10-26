extends Node3D
## A locked warning lane followed by a travelling, first-hit skillshot.
const S = preload("res://scripts/shapes.gd")
const Roles = preload("res://scripts/archetypes.gd")
var source: Node3D
var direction := Vector3.RIGHT
var windup := Roles.THROW_WINDUP
var remaining := Roles.THROW_RANGE
var visuals_enabled := true
var warning: Node3D
var projectile: Node3D
var radius := Roles.THROW_RADIUS
var speed := Roles.THROW_SPEED
var stun_seconds := Roles.STUN_SECONDS
var mobile_cast := false


func _ready() -> void:
	if not visuals_enabled:
		return
	var accent := S.material(Color("#ff95c1"), true)
	var danger := S.material(Color("#ffe1ee"), true)
	warning = Node3D.new()
	add_child(warning)
	warning.rotation.y = atan2(-direction.x, -direction.z)
	for side in [-1, 1]:
		S.rod(warning, Vector3(side * radius, 0.10, 0),
			Vector3(side * radius, 0.10, -remaining), 0.045, accent)
	for i in range(6):
		var z := -remaining * (i + 0.5) / 6.0
		S.rod(warning, Vector3(-0.35, 0.11, z + 0.4), Vector3(0, 0.11, z), 0.04, danger)
		S.rod(warning, Vector3(0.35, 0.11, z + 0.4), Vector3(0, 0.11, z), 0.04, danger)
	projectile = Node3D.new()
	add_child(projectile)
	projectile.rotation.y = warning.rotation.y
	# A bright star baton has a distinct silhouette from the round football.
	for i in range(4):
		var blade := S.box(projectile, Vector3(0, 1.1, 0), Vector3(radius * 1.9, 0.13, 0.13), accent)
		blade.rotation.z = i * PI / 4
	S.sphere(projectile, Vector3(0, 1.1, 0), radius * 0.32, danger)
	for side in [-1, 0, 1]:
		S.rod(projectile, Vector3(side * radius * 0.4, 1.1, 0.3), Vector3(side * radius * 0.4, 1.1, 2.2 - abs(side) * 0.5), 0.045, danger)
	projectile.visible = false


func show_flight() -> void:
	if visuals_enabled:
		warning.visible = false
		projectile.visible = true
		projectile.rotation.x = sin(remaining * 0.9) * 0.18
