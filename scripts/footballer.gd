extends Node3D

const S = preload("res://scripts/shapes.gd")
const Roles = preload("res://scripts/archetypes.gd")
const Gear = preload("res://scripts/equipment.gd")
const RUN_SPEED := 7.8

var archetype := Roles.Kind.RUNNER
var visuals_enabled := true
var team := 0
var shirt_number := 10
var human := false
var local_controlled := true
var goalkeeper := false
var tactical_line := 3
var home := Vector3.ZERO
var target := Vector3.ZERO
var facing := Vector3.RIGHT
var velocity := Vector3.ZERO
var kick_cooldown := 0.0
var decision_time := 0.0
var ability_time := 0.0
var ability_cooldown := 0.0
var slow_multiplier := 1.0
var charging := false
var charge_time := 0.0
var ai_charge_goal := 0.0
var dash_remaining := 0.0
var dash_direction := Vector3.RIGHT
var dash_flash := 0.0
var ai_skill_wait := 0.0
var ai_skill_pending := false
var ai_contesting := false
var ai_think_wait := 0.0
var ai_turn_error := 0.0
var ai_turn_speed := deg_to_rad(240.0)
var ai_aim_direction := Vector3.ZERO
var ai_aim_error := 0.0
var ai_kick_power := 0.0
var ai_kick_kind := "shot"
var ai_pass_target: Node3D
var ai_poke := false
var ai_kick_wait := 0.0
var ai_receive_time := 0.0
var ai_receive_direction := Vector3.ZERO
var ai_tackle_target: Node3D
var ai_tackle_wait := 0.0
var gait := 0.0
var kick_pose := 0.0
var body: Node3D
var left_leg: Node3D
var right_leg: Node3D
var left_arm: Node3D
var right_arm: Node3D
var selection: MeshInstance3D
var direction_marker: Node3D
var skill_ring: Node3D
var role_parts: Node3D
var left_sleeve: Node3D
var right_sleeve: Node3D
var charge_arrow: Node3D
var dash_trail: Node3D
var slow_effect: Node3D
var stats: Dictionary
var gold := Gear.START_GOLD
var inventory: Array[int] = []
var build_variant := 0
var possession_income := 0.0
var defense_reward_wait := 0.0
var stun_time := 0.0
var throw_windup := 0.0
var save_time := 0.0
var ai_save_wait := -1.0
var you_tag: Label3D
var left_glove: MeshInstance3D
var right_glove: MeshInstance3D
var team_speed_multiplier := 1.0
var team_purchases := [0, 0]
var evolution_times := [-1.0, -1.0]
var e_selected := -1
var e_charges: Dictionary = {}
var e_cooldown := 0.0
var e_boost_time := 0.0
var e_boost_multiplier := 1.0
var e_immunity_time := 0.0
var ai_e_wait := -1.0
var e_effect: Node3D
var stun_stars: Node3D
var rogue_player := false
var w_unlocked := true
var e_unlimited := false
var extra_bonuses: Dictionary = {}


func _ready() -> void:
	if visuals_enabled:
		_build_model()
	reset_position(true)


func reset_position(fresh_match: bool = false) -> void:
	position = home
	target = home
	facing = Vector3.RIGHT if team == 0 else Vector3.LEFT
	velocity = Vector3.ZERO
	kick_cooldown = 0.0
	decision_time = 0.7
	ability_time = 0.0
	slow_multiplier = 1.0
	cancel_charge()
	dash_remaining = 0.0
	dash_flash = 0.0
	ai_skill_wait = 0.0
	ai_skill_pending = false
	ai_contesting = false
	ai_think_wait = 0.0
	ai_turn_error = 0.0
	ai_aim_direction = Vector3.ZERO
	ai_aim_error = 0.0
	ai_kick_power = 0.0
	ai_kick_kind = "shot"
	ai_pass_target = null
	ai_poke = false
	ai_kick_wait = 0.0
	ai_receive_time = 0.0
	ai_tackle_target = null
	ai_tackle_wait = 0.0
	stun_time = 0.0
	throw_windup = 0.0
	save_time = 0.0
	ai_save_wait = -1.0
	e_boost_time = 0.0
	e_boost_multiplier = 1.0
	e_immunity_time = 0.0
	ai_e_wait = -1.0
	if fresh_match:
		e_selected = -1
		e_charges.clear()
		e_cooldown = 0.0
		evolution_times = [-1.0, -1.0]
		team_speed_multiplier = 1.0
		team_purchases = [0, 0]
		gold = Gear.START_GOLD
		inventory.clear()
		possession_income = 0.0
		defense_reward_wait = 0.0
		ability_cooldown = 0.0
		stats = {
			"tackles": 0, "turnovers": 0, "interceptions": 0, "recoveries": 0,
			"possession_seconds": 0.0, "goals": 0, "own_goals": 0, "kicks": 0, "casts": 0,
			"gold_earned": 0, "stuns": 0, "stun_seconds": 0.0, "save_attempts": 0, "saves": 0,
			"e_casts": 0, "domain_slow_seconds": 0.0
		}
		if visuals_enabled:
			_build_role_style()
	if visuals_enabled:
		animate(0.0)


func hit_scale() -> float:
	return (1.0 if rogue_player else Roles.HIT_SCALE[archetype]) * (1.0 + equipment_bonus("size"))


func equipment_bonus(key: String) -> float:
	var value: float = extra_bonuses.get(key, 0.0)
	for item_id in inventory:
		value += Gear.ITEMS[item_id].bonuses.get(key, 0.0)
	return value


func ability_duration() -> float:
	return Roles.DURATION[archetype] + equipment_bonus("duration")


func ability_max_cooldown() -> float:
	return Roles.COOLDOWN[archetype] / (1.0 + equipment_bonus("haste"))


func slow_radius() -> float:
	return Roles.SLOW_RADIUS + equipment_bonus("radius")


func max_charge_time() -> float:
	return Roles.CHARGE_DURATION * (1.0 - equipment_bonus("charge"))


func max_dash_distance() -> float:
	return Roles.DASH_MAX_DISTANCE + equipment_bonus("dash")


func refresh_equipment() -> void:
	if visuals_enabled:
		_build_role_style()


func collision_radius() -> float:
	return 0.51 * hit_scale()


func control_distance() -> float:
	return 1.05 + collision_radius() - 0.51


func move_speed() -> float:
	var passive: float = Roles.SPEED[archetype]
	if archetype == Roles.Kind.WARDEN:
		passive = 1.1 if position.x * (1.0 if team == 0 else -1.0) <= 0.0 else 0.85
	if rogue_player:
		passive = 1.0
	var speed: float = RUN_SPEED * passive * (1.0 + equipment_bonus("speed"))
	var boost := e_boost_multiplier if e_boost_time > 0.0 else 1.0
	if archetype == Roles.Kind.RUNNER and ability_time > 0.0:
		boost = maxf(boost, Roles.SPRINT_MULTIPLIER + equipment_bonus("sprint"))
	return speed * slow_multiplier * team_speed_multiplier * boost


func slow_resistance() -> float:
	return minf(0.7, equipment_bonus("slow_resist"))


func domain_radius() -> float:
	return Roles.DOMAIN_RADIUS + equipment_bonus("domain_radius")


func domain_range() -> float:
	return Roles.DOMAIN_RANGE + equipment_bonus("domain_range")


func throw_radius() -> float:
	return Roles.THROW_RADIUS


func throw_speed() -> float:
	return Roles.THROW_SPEED * (1.0 + equipment_bonus("throw_speed"))


func throw_range() -> float:
	return Roles.THROW_RANGE + equipment_bonus("throw_range")


func throw_stun() -> float:
	return Roles.STUN_SECONDS


func mobile_throw() -> bool:
	return archetype == Roles.Kind.STRIKER


func save_window() -> float:
	return Roles.SAVE_WINDOW + equipment_bonus("save_window")


func keeper_radius() -> float:
	return Roles.KEEPER_SLOW_RADIUS + equipment_bonus("keeper_radius")


func charge_fraction() -> float:
	return charge_time / max_charge_time()


func dash_distance() -> float:
	return lerpf(Roles.DASH_MIN_DISTANCE, max_dash_distance(), charge_fraction())


func cancel_charge() -> void:
	charging = false
	charge_time = 0.0


func set_archetype(kind: int) -> void:
	archetype = kind
	if visuals_enabled:
		_build_role_style()


func action_blocked() -> bool:
	return stun_time > 0.0 or throw_windup > 0.0


func constrain_position(point: Vector3) -> Vector3:
	var radius := collision_radius()
	point.x = clampf(point.x, -48 + radius, 48 - radius)
	point.z = clampf(point.z, -30 + radius, 30 - radius)
	if archetype == Roles.Kind.KEEPER:
		point.x = clampf(point.x, -48 + radius, -32 - radius) if team == 0 else clampf(point.x, 32 + radius, 48 - radius)
		point.z = clampf(point.z, -16 + radius, 16 - radius)
	point.y = 0.0
	return point


func step(delta: float, others: Array) -> void:
	kick_cooldown = maxf(0.0, kick_cooldown - delta)
	ai_receive_time = maxf(0.0, ai_receive_time - delta)
	decision_time = maxf(0.0, decision_time - delta)
	ability_time = maxf(0.0, ability_time - delta)
	ability_cooldown = maxf(0.0, ability_cooldown - delta)
	e_cooldown = maxf(0.0, e_cooldown - delta)
	e_boost_time = maxf(0.0, e_boost_time - delta)
	e_immunity_time = maxf(0.0, e_immunity_time - delta)
	dash_flash = maxf(0.0, dash_flash - delta)
	ai_skill_wait = maxf(0.0, ai_skill_wait - delta)
	stun_time = maxf(0.0, stun_time - delta)
	throw_windup = maxf(0.0, throw_windup - delta)
	save_time = maxf(0.0, save_time - delta)
	target = constrain_position(target)
	if charging:
		charge_time = minf(max_charge_time(), charge_time + delta)
	if stun_time > 0.0 or (throw_windup > 0.0 and not mobile_throw()):
		velocity = Vector3.ZERO
	elif dash_remaining > 0.0:
		var travel := minf(Roles.DASH_SPEED * slow_multiplier * team_speed_multiplier * delta, dash_remaining)
		facing = dash_direction
		velocity = dash_direction * travel / delta
		position += dash_direction * travel
		dash_remaining = maxf(0.0, dash_remaining - travel)
		dash_flash = 0.18
		if dash_remaining <= 0.0:
			target = position
			velocity = Vector3.ZERO
	else:
		var offset := target - position
		offset.y = 0.0
		var desired := Vector3.ZERO
		if not human and ai_kick_power > 0.0:
			_turn_ai(ai_aim_direction, delta)
		elif offset.length() > 0.18:
			desired = offset.normalized() * minf(move_speed(), offset.length() / delta)
			if human:
				facing = facing.lerp(offset.normalized(), minf(1.0, delta * 18.0)).normalized()
			else:
				desired = desired.rotated(Vector3.UP, ai_turn_error)
				if ai_receive_time <= 0.0:
					_turn_ai(desired.normalized(), delta)
		if not human and ai_receive_time > 0.0 and ai_kick_power <= 0.0:
			var previous_speed := ai_turn_speed
			ai_turn_speed = deg_to_rad(preload("res://scripts/npc_tactics.gd").TUNE.receive_turn)
			_turn_ai(ai_receive_direction, delta)
			ai_turn_speed = previous_speed
		velocity = velocity.move_toward(desired, 45.0 * delta)
		position += velocity * delta
	# Soft body separation; no navigation mesh is needed on an empty pitch.
	var radius := collision_radius()
	for other in others:
		if other == self:
			continue
		var gap: Vector3 = position - other.position
		var distance := gap.length()
		var separation: float = radius + other.collision_radius()
		if distance < separation and distance > 0.001:
			position += gap / distance * (separation - distance) * 0.45
	var unclamped := position
	position = constrain_position(position)
	if dash_remaining > 0.0 and position != unclamped:
		dash_remaining = 0.0
		target = position
		velocity = Vector3.ZERO
	gait += velocity.length() * delta * 1.7
	kick_pose = maxf(0.0, kick_pose - delta * 5.0)
	if visuals_enabled:
		animate(delta)


func _turn_ai(direction: Vector3, delta: float) -> void:
	var angle := facing.signed_angle_to(direction, Vector3.UP)
	facing = facing.rotated(Vector3.UP, clampf(angle, -ai_turn_speed * delta, ai_turn_speed * delta)).normalized()


func animate(delta: float) -> void:
	var stride := sin(gait) * minf(velocity.length() / RUN_SPEED, 1.25) * 0.7
	left_leg.rotation.x = stride
	right_leg.rotation.x = -stride - kick_pose * 1.25
	left_arm.rotation.x = -stride * 0.8
	right_arm.rotation.x = stride * 0.8
	body.rotation.y = atan2(-facing.x, -facing.z)
	body.position.y = absf(sin(gait)) * minf(velocity.length(), 8.0) * 0.009
	selection.visible = human and local_controlled
	direction_marker.visible = human and local_controlled
	you_tag.visible = human and local_controlled
	stun_stars.visible = stun_time > 0.0
	stun_stars.rotation.y += delta * 4.5
	e_effect.visible = e_boost_time > 0.0 or e_immunity_time > 0.0
	if human:
		direction_marker.rotation.y = body.rotation.y
		selection.scale = Vector3.ONE * hit_scale() * (1.08 if ability_time > 0.0 else 1.0)
	skill_ring.visible = ability_time > 0.0 or charging or dash_flash > 0.0
	skill_ring.rotation.y += delta * 2.0
	if archetype == Roles.Kind.KEEPER:
		skill_ring.rotation.y = body.rotation.y
	skill_ring.scale = Vector3.ONE * (0.7 + charge_fraction() * 0.6 if charging else 1.0)
	charge_arrow.visible = charging
	charge_arrow.rotation.y = body.rotation.y
	charge_arrow.scale.z = dash_distance()
	if archetype == Roles.Kind.KEEPER:
		charge_arrow.visible = save_time > 0.0
		charge_arrow.scale = Vector3.ONE
		for glove in [left_glove, right_glove]:
			glove.position.y = 1.65 if save_time > 0.0 else 0.91
			glove.position.z = -0.65 if save_time > 0.0 else -0.14
	if charging:
		body.rotation.x = -0.18 * charge_fraction()
	else:
		body.rotation.x = -0.25 if dash_remaining > 0.0 else 0.0
	var sprinting := archetype == Roles.Kind.RUNNER and ability_time > 0.0
	dash_trail.visible = dash_flash > 0.0 or sprinting
	var trail_direction := facing if sprinting else dash_direction
	dash_trail.rotation.y = atan2(-trail_direction.x, -trail_direction.z)
	dash_trail.scale.z = 0.9 + sin(ability_time * 18) * 0.15 if sprinting else dash_flash / 0.18
	slow_effect.visible = slow_multiplier < 1.0
	if throw_windup > 0.0:
		right_arm.rotation.x = -2.3
	if save_time > 0.0:
		left_arm.rotation.x = -1.5
		right_arm.rotation.x = -1.5
	left_sleeve.transform = left_arm.transform
	right_sleeve.transform = right_arm.transform


func status_text() -> String:
	var parts: Array[String] = []
	if stun_time > 0.0:
		parts.append("眩晕 %.1fs" % stun_time)
	if slow_multiplier < 1.0:
		parts.append("减速 %d%%" % roundi((1.0 - slow_multiplier) * 100))
	if charging:
		parts.append("W %d%%" % roundi(charge_fraction() * 100))
	if throw_windup > 0.0:
		parts.append("W 移动施法")
	if e_immunity_time > 0.0:
		parts.append("免控 %.1fs" % e_immunity_time)
	if e_boost_time > 0.0:
		parts.append("加速 %.1fs" % e_boost_time)
	elif archetype == Roles.Kind.RUNNER and ability_time > 0.0:
		parts.append("疾跑 %.1fs" % ability_time)
	return " · ".join(parts)


func _build_model() -> void:
	var shirt_color := Color("#1973d6") if team == 0 else Color("#e24649")
	if goalkeeper:
		shirt_color = Color("#eac944") if team == 0 else Color("#9f82cf")
	var shirt := S.material(shirt_color)
	var shorts := S.material(Color("#e3e7ec") if team == 0 else Color("#20252e"))
	var skin_colors := [Color("#cb9978"), Color("#8d6049"), Color("#e5ba98"), Color("#6f4938")]
	var skin := S.material(skin_colors[shirt_number % 4])
	var sock := S.material(Color("#e7ebef"))
	var boot := S.material(Color("#16191f"))
	var hair := S.material(Color("#382c29"))
	body = Node3D.new()
	add_child(body)
	body.scale = Vector3.ONE * 1.22
	S.capsule(body, Vector3(0, 1.18, 0), 0.32, 0.74, shirt).scale = Vector3(1.04, 1.0, 0.66)
	S.capsule(body, Vector3(0, 0.79, 0), 0.28, 0.56, shorts).scale = Vector3(1, 0.50, 0.68)
	S.box(body, Vector3(0, 1.53, 0), Vector3(0.2, 0.15, 0.2), skin)
	S.sphere(body, Vector3(0, 1.78, -0.01), 0.23, skin)
	S.sphere(body, Vector3(0, 1.92, 0.025), 0.215, hair).scale.y = 0.6
	# Collar, shirt seams and a small original club badge.
	S.ring(body, Vector3(0, 1.49, 0), 0.13, 0.035, shorts).scale.z = 0.72
	for side in [-1, 1]:
		S.box(body, Vector3(side * 0.29, 1.16, -0.05), Vector3(0.035, 0.43, 0.25), sock)
		S.sphere(body, Vector3(side * 0.075, 1.81, -0.215), 0.017, hair)
	S.sphere(body, Vector3(0, 1.77, -0.235), 0.035, skin).scale.z = 1.5
	S.box(body, Vector3(-0.14, 1.30, -0.218), Vector3(0.09, 0.11, 0.015), sock)
	var crest := Label3D.new()
	crest.text = "LS"
	crest.font_size = 32
	crest.pixel_size = 0.0035
	crest.outline_size = 0
	crest.position = Vector3(0.09, 1.30, -0.224)
	crest.rotation.y = PI
	body.add_child(crest)
	left_leg = _limb(Vector3(-0.19, 0.75, 0), Vector3(0.21, 0.48, 0.23), shorts, sock, true, boot, skin)
	right_leg = _limb(Vector3(0.19, 0.75, 0), Vector3(0.21, 0.48, 0.23), shorts, sock, true, boot, skin)
	left_arm = _limb(Vector3(-0.35, 1.43, 0), Vector3(0.22, 0.34, 0.25), shirt, skin, false, boot, skin)
	right_arm = _limb(Vector3(0.35, 1.43, 0), Vector3(0.22, 0.34, 0.25), shirt, skin, false, boot, skin)
	var number := Label3D.new()
	number.text = str(shirt_number)
	number.font_size = 60
	number.pixel_size = 0.006
	number.outline_size = 0
	number.position = Vector3(0, 1.2, 0.2)
	number.rotation.y = 0.0
	body.add_child(number)
	var ring_mat := S.material(Color("#dff78d") if human else shirt_color.darkened(0.05), true)
	selection = S.ring(self, Vector3(0, 0.035, 0), 0.82, 0.1, ring_mat)
	var shadow_mat := S.material(Color("#2c5e46"))
	S.sphere(self, Vector3(0, 0.025, 0), 0.54, shadow_mat).scale = Vector3(1, 0.015, 0.7)
	slow_effect = Node3D.new()
	add_child(slow_effect)
	var slow_mat := S.material(Color("#ffc66b"), true)
	S.ring(slow_effect, Vector3(0, 0.12, 0), 0.68, 0.12, slow_mat)
	direction_marker = Node3D.new()
	add_child(direction_marker)
	S.rod(direction_marker, Vector3(0, 0.045, -1.25), Vector3(0, 0.045, -2.15), 0.045, ring_mat)
	S.rod(direction_marker, Vector3(-0.28, 0.045, -1.82), Vector3(0, 0.045, -2.15), 0.045, ring_mat)
	S.rod(direction_marker, Vector3(0.28, 0.045, -1.82), Vector3(0, 0.045, -2.15), 0.045, ring_mat)
	you_tag = Label3D.new()
	you_tag.text = "▼"
	you_tag.font_size = 30
	you_tag.pixel_size = 0.012
	you_tag.modulate = Color("#c9ff41")
	you_tag.outline_modulate = Color("#11151a")
	you_tag.outline_size = 8
	you_tag.position.y = 2.9
	you_tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	add_child(you_tag)
	e_effect = Node3D.new()
	add_child(e_effect)
	S.ring(e_effect, Vector3.UP * 0.2, 0.95, 0.06, S.material(Color("#f6efa6"), true))
	stun_stars = Node3D.new()
	add_child(stun_stars)
	var star_mat := S.material(Color("#ffe38b"), true)
	for i in range(3):
		var at := Vector3(cos(i * TAU / 3) * 0.7, 2.8, sin(i * TAU / 3) * 0.7)
		for angle in [0.0, PI / 2]:
			var star := S.box(stun_stars, at, Vector3(0.34, 0.075, 0.075), star_mat)
			star.rotation.z = angle + PI / 4
	_build_role_style()


func _build_role_style() -> void:
	if role_parts != null:
		role_parts.free()
		skill_ring.free()
		charge_arrow.free()
		dash_trail.free()
	role_parts = Node3D.new()
	body.add_child(role_parts)
	left_sleeve = Node3D.new()
	right_sleeve = Node3D.new()
	role_parts.add_child(left_sleeve)
	role_parts.add_child(right_sleeve)
	skill_ring = Node3D.new()
	add_child(skill_ring)
	charge_arrow = Node3D.new()
	add_child(charge_arrow)
	dash_trail = Node3D.new()
	add_child(dash_trail)
	var accent := S.material(Roles.COLORS[archetype])
	var light := S.material(Roles.COLORS[archetype], true)
	var armor := S.material(Color("#252a32"))
	body.scale = Vector3(1.22, 1.22, 1.22) * Vector3(1.0 + equipment_bonus("size"), 1.0, 1.0 + equipment_bonus("size"))
	# Role cues are sportswear: armbands, compression sleeves and protective pads.
	S.box(left_sleeve, Vector3(0, -0.14, 0), Vector3(0.235, 0.09, 0.265), accent)
	match archetype:
		Roles.Kind.RUNNER:
			for side in [-1, 1]:
				S.box(role_parts, Vector3(side * 0.19, 0.20, -0.02), Vector3(0.22, 0.065, 0.24), accent)
			S.ring(skill_ring, Vector3(0, 0.06, 0), 1.0, 0.045, light)
			for side in [-1, 0, 1]:
				S.rod(dash_trail, Vector3(side * 0.4, 0.3, 0.4), Vector3(side * 0.4, 0.3, 2.0 - abs(side) * 0.4), 0.045, light)
		Roles.Kind.GUARD:
			body.scale *= Vector3(Roles.HIT_SCALE[archetype], 1.03, Roles.HIT_SCALE[archetype])
			for side in [-1, 1]:
				S.capsule(left_sleeve if side == -1 else right_sleeve, Vector3(0, -0.01, 0), 0.12, 0.27, armor)
				S.box(role_parts, Vector3(side * 0.19, 0.38, -0.14), Vector3(0.21, 0.17, 0.07), armor)
			S.ring(skill_ring, Vector3(0, 0.07, 0), slow_radius(), 0.065, light)
			for i in range(8):
				var radial := Vector3(cos(i * TAU / 8), 0, sin(i * TAU / 8))
				S.sphere(skill_ring, radial * slow_radius() + Vector3.UP * 0.14, 0.13, light)
		Roles.Kind.CHARGER:
			for side in [-1, 1]:
				S.capsule(left_sleeve if side == -1 else right_sleeve, Vector3(0, -0.25, 0), 0.105, 0.34, armor)
			S.ring(skill_ring, Vector3(0, 0.08, 0), 1.3, 0.05, light)
			S.box(charge_arrow, Vector3(0, 0.09, -0.5), Vector3(0.07, 0.04, 1.0), light)
			for side in [-1, 1]:
				S.rod(charge_arrow, Vector3(side * 0.45, 0.09, -0.86), Vector3(0, 0.09, -1), 0.035, light)
				S.rod(dash_trail, Vector3(side * 0.4, 0.2, 0.2), Vector3(side * 0.4, 0.2, 2.4), 0.035, light)
		Roles.Kind.STRIKER:
			S.box(left_sleeve, Vector3(0, -0.14, -0.14), Vector3(0.18, 0.08, 0.025), armor)
			S.capsule(right_sleeve, Vector3(0, -0.39, 0), 0.11, 0.22, accent)
		Roles.Kind.WARDEN:
			for side in [-1, 1]:
				S.box(role_parts, Vector3(side * 0.23, 1.43, -0.05), Vector3(0.13, 0.06, 0.30), accent)
		Roles.Kind.KEEPER:
			for side in [-1, 1]:
				var glove := S.capsule(role_parts, Vector3(side * 0.35, 0.91, -0.14), 0.15, 0.36, accent)
				if side == -1:
					left_glove = glove
				else:
					right_glove = glove
				S.box(role_parts, Vector3(side * 0.2, 0.44, -0.13), Vector3(0.24, 0.24, 0.10), armor)
			S.ring(charge_arrow, Vector3(0, 0.12, 0), Roles.SAVE_REACH * hit_scale() * (1.0 + equipment_bonus("pickup")), 0.055, light)
			var last := Vector3.ZERO
			for i in range(25):
				var angle := lerpf(-Roles.KEEPER_CONE_HALF_ANGLE, Roles.KEEPER_CONE_HALF_ANGLE, i / 24.0)
				var point := Vector3(sin(angle), 0, -cos(angle)) * keeper_radius() + Vector3.UP * 0.08
				if i > 0:
					S.rod(skill_ring, last, point, 0.045, light)
				if i == 0 or i == 24:
					S.rod(skill_ring, Vector3.UP * 0.08, point, 0.035, light)
				last = point
	skill_ring.visible = false
	charge_arrow.visible = false
	dash_trail.visible = false


func _limb(at: Vector3, size: Vector3, upper: Material, lower: Material, leg: bool, boot: Material, skin: Material) -> Node3D:
	var pivot := Node3D.new()
	pivot.position = at
	body.add_child(pivot)
	if leg:
		S.capsule(pivot, Vector3(0, -0.12, 0), size.x * 0.53, 0.28, upper)
		S.capsule(pivot, Vector3(0, -0.32, 0), size.x * 0.46, 0.24, skin)
		S.capsule(pivot, Vector3(0, -0.51, 0), size.x * 0.43, 0.28, lower)
		S.box(pivot, Vector3(0, -0.67, -0.08), Vector3(0.24, 0.14, 0.36), boot)
	else:
		S.capsule(pivot, Vector3(0, -size.y * 0.5, 0), size.x * 0.5, size.y + 0.07, upper)
		S.capsule(pivot, Vector3(0, -size.y - 0.1, 0), size.x * 0.41, 0.29, lower)
	return pivot
