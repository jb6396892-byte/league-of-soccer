extends Node3D

const S = preload("res://scripts/shapes.gd")
const HALF_LENGTH := 48.0
const HALF_WIDTH := 30.0
const GOAL_HALF_WIDTH := 5.2
const GOAL_HEIGHT := 3.2


func _ready() -> void:
	var grass := ShaderMaterial.new()
	grass.shader = preload("res://shaders/pitch.gdshader")
	var white := S.material(Color("#edf3ec"))
	var dark := S.material(Color("#18201b"))
	var concrete := S.material(Color("#20262d"))
	var navy := S.material(Color("#11151e"))
	var lime := S.material(Color("#c9ff41"), true)
	S.box(self, Vector3(0, -0.55, 0), Vector3(116, 1, 78), dark)
	S.box(self, Vector3(0, -0.11, 0), Vector3(96, 0.2, 60), grass)
	_rectangle(Vector3.ZERO, Vector2(96, 60), white)
	_line(Vector3(0, 0, -30), Vector3(0, 0, 30), white)
	S.ring(self, Vector3(0, 0.04, 0), 8.2, 0.12, white)
	_spot(Vector3.ZERO, white)
	for side in [-1, 1]:
		_rectangle(Vector3(side * 40, 0, 0), Vector2(16, 32), white)
		_rectangle(Vector3(side * 45, 0, 0), Vector2(6, 15), white)
		_spot(Vector3(side * 37, 0, 0), white)
		_goal(side, white)
		for z in [-30, 30]:
			S.rod(self, Vector3(side * 48, 0, z), Vector3(side * 48, 2, z), 0.055, white)
			S.box(self, Vector3(side * 48 + 0.35, 1.8, z), Vector3(0.7, 0.4, 0.035), lime)
		# Low terraces keep the view of the playing field unobstructed.
		for tier in range(6):
			S.box(self, Vector3(0, 0.25 + tier * 0.58, side * (35.8 + tier * 1.7)), Vector3(106, 0.55, 1.65), concrete)
			for seat in range(53):
				var color := navy if (seat + tier) % 5 < 3 else dark
				S.box(self, Vector3(-51 + seat * 2, 0.65 + tier * 0.58, side * (35.8 + tier * 1.7)), Vector3(1.3, 0.22, 0.85), color)
		# Advertising boards.
		for i in range(7):
			var x := -45.0 + i * 15.0
			S.box(self, Vector3(x, 0.7, side * 32.5), Vector3(14.5, 1.3, 0.22), navy)
			var label := Label3D.new()
			label.text = "LEAGUE OF SOCCER" if i % 2 == 0 else "SMGBRO  FOOTBALL"
			label.font_size = 60
			label.pixel_size = 0.007
			label.modulate = Color("#c9ff41") if i % 2 == 0 else Color("#e5e8ed")
			label.outline_size = 0
			label.position = Vector3(x, 0.75, side * 32.34)
			label.rotation.y = PI if side > 0 else 0.0
			add_child(label)
	for x in [-54, 54]:
		for z in [-33, 33]:
			S.rod(self, Vector3(x, 0, z), Vector3(x, 18, z), 0.18, navy)
			S.box(self, Vector3(x, 18, z), Vector3(4.2, 1.8, 0.35), navy)
			var lamp := S.material(Color("#e6f0ff"), true)
			for row in range(2):
				for column in range(5):
					S.box(self, Vector3(x - 1.6 + column * 0.8, 17.6 + row * 0.8, z - signf(z) * 0.23), Vector3(0.62, 0.6, 0.08), lamp)
	# Lower banks above the centre stands remain visible from the touchline.
	for x in [-22, 22]:
		for side in [-1, 1]:
			var z: float = side * 44.0
			S.rod(self, Vector3(x, 0, z), Vector3(x, 10, z), 0.13, navy)
			S.box(self, Vector3(x, 10, z), Vector3(3.8, 0.9, 0.25), navy)
			for bulb in range(5):
				S.box(self, Vector3(x - 1.45 + bulb * 0.73, 10, z - side * 0.18), Vector3(0.58, 0.6, 0.07), S.material(Color("#e6f0ff"), true))


func _line(a: Vector3, b: Vector3, mat: Material) -> void:
	a.y = 0.035
	b.y = 0.035
	S.rod(self, a, b, 0.065, mat).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _rectangle(center: Vector3, size: Vector2, mat: Material) -> void:
	var x := size.x * 0.5
	var z := size.y * 0.5
	_line(center + Vector3(-x, 0, -z), center + Vector3(x, 0, -z), mat)
	_line(center + Vector3(x, 0, -z), center + Vector3(x, 0, z), mat)
	_line(center + Vector3(x, 0, z), center + Vector3(-x, 0, z), mat)
	_line(center + Vector3(-x, 0, z), center + Vector3(-x, 0, -z), mat)


func _spot(at: Vector3, mat: Material) -> void:
	S.sphere(self, at + Vector3(0, 0.03, 0), 0.19, mat).scale.y = 0.1


func _goal(side: int, mat: Material) -> void:
	var x := side * HALF_LENGTH
	var back := x + side * 2.8
	var net := S.material(Color("#9ab6a8"))
	for z in [-GOAL_HALF_WIDTH, GOAL_HALF_WIDTH]:
		S.rod(self, Vector3(x, 0, z), Vector3(x, GOAL_HEIGHT, z), 0.13, mat)
		S.rod(self, Vector3(x, GOAL_HEIGHT, z), Vector3(back, GOAL_HEIGHT, z), 0.07, mat)
		S.rod(self, Vector3(back, 0, z), Vector3(back, GOAL_HEIGHT, z), 0.07, mat)
		for height in range(1, 7):
			S.rod(self, Vector3(x, height * 0.5, z), Vector3(back, height * 0.5, z), 0.018, net)
		for column in range(1, 6):
			var nx := x + side * column * 0.5
			S.rod(self, Vector3(nx, 0, z), Vector3(nx, GOAL_HEIGHT, z), 0.018, net)
	S.rod(self, Vector3(x, GOAL_HEIGHT, -GOAL_HALF_WIDTH), Vector3(x, GOAL_HEIGHT, GOAL_HALF_WIDTH), 0.13, mat)
	for row in range(7):
		S.rod(self, Vector3(back, row * 0.5, -GOAL_HALF_WIDTH), Vector3(back, row * 0.5, GOAL_HALF_WIDTH), 0.018, net)
	for column in range(21):
		var z := -5.0 + column * 0.5
		S.rod(self, Vector3(back, 0, z), Vector3(back, GOAL_HEIGHT, z), 0.018, net)
		S.rod(self, Vector3(x, GOAL_HEIGHT, z), Vector3(back, GOAL_HEIGHT, z), 0.018, net)
