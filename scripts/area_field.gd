extends Node3D
## Fixed ground area; gameplay ticks it only during active match time.
const S = preload("res://scripts/shapes.gd")
var team := 0
var source: Node3D
var radius := 10.0
var remaining := 12.0
var multiplier := 0.7
var title := "镇守领域"
var visuals_enabled := true
var label_text := ""
var lifetime := 12.0
var ripple: MeshInstance3D
var rim_ticks: Array[MeshInstance3D] = []


func _ready() -> void:
	if not visuals_enabled:
		return
	lifetime = remaining
	var color := Color("#69cfff") if team == 0 else Color("#ff846d")
	var material := S.material(color, true)
	S.ring(self, Vector3.UP * 0.09, radius, 0.12, material)
	var soft := S.material(Color(color, 0.12), true)
	soft.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var disc := CylinderMesh.new()
	disc.top_radius = radius
	disc.bottom_radius = radius
	disc.height = 0.015
	disc.radial_segments = 48
	S.mesh(self, disc, Vector3.UP * 0.035, soft)
	ripple = S.ring(self, Vector3.UP * 0.055, radius, 0.07, soft)
	for i in range(12):
		var angle := i * TAU / 12
		var radial := Vector3(cos(angle), 0, sin(angle))
		var tick := S.box(self, radial * (radius - 0.6) + Vector3.UP * 0.12, Vector3(0.75, 0.08, 0.22), material)
		tick.rotation.y = -angle
		rim_ticks.append(tick)
	update_label()


func update_label() -> void:
	if visuals_enabled:
		label_text = "%s · -%d%% · %ds" % [title, roundi((1.0 - multiplier) * 100), ceili(remaining)]
		var age := lifetime - remaining
		ripple.scale = Vector3.ONE * (0.75 + fmod(age * 0.22, 0.25))
		for i in range(rim_ticks.size()):
			rim_ticks[i].visible = i < ceili(12 * remaining / lifetime)
