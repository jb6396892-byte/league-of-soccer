extends SceneTree

const Roles = preload("res://scripts/archetypes.gd")
var failures := 0
var checks := 0


func check(condition: bool, message: String) -> void:
	checks += 1
	if condition:
		print("PASS: " + message)
	else:
		failures += 1
		printerr("FAIL: " + message)


func _initialize() -> void:
	call_deferred("run")


func key_event(game: Node, key: Key, pressed: bool, echo: bool = false) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = key
	event.pressed = pressed
	event.echo = echo
	game._unhandled_input(event)


func run() -> void:
	var game = load("res://main.tscn").instantiate()
	game.simulation_mode = true
	root.add_child(game)
	game.set_physics_process(false)
	game.start_match()
	game.reset_kickoff(0)
	var actor = game.player
	actor.human = true
	check(game.players.size() == 22, "22 players remain")
	actor.archetype = Roles.Kind.RUNNER
	check(is_equal_approx(actor.move_speed(), 7.8 * 1.05), "runner passive adds 5 percent speed")
	check(game.use_ability(actor), "runner W activates once")
	check(actor.ability_time == 2.0 and actor.ability_cooldown == 12.0, "runner lasts 2s with 12s cooldown")
	check(not game.use_ability(actor), "repeat W cannot refresh sprint")
	check(is_equal_approx(actor.move_speed(), 7.8 * 1.05 * Roles.SPRINT_MULTIPLIER), "sprint applies configured speed multiplier")
	for i in range(121):
		actor.step(1.0 / 60, [])
	check(actor.ability_time == 0 and actor.ability_cooldown > 7.9, "one-shot sprint ends without another key press")
	# Isolate the field from normal close-range tackles.
	for other in game.players:
		other.reset_position(true)
		other.position = Vector3(-35, 0, 22)
	actor.archetype = Roles.Kind.GUARD
	check(is_equal_approx(actor.collision_radius(), 0.51 * 1.1) and actor.hit_scale() == 1.1, "guard body and interaction ranges enlarged 10 percent")
	actor.position = Vector3.ZERO
	actor.target = actor.position
	game.carrier = null
	game.possession_lock = 0
	game.ball.position = Vector3(0, 0.34, 1.23)
	game.ball.velocity = Vector3.ZERO
	game._update_possession(1.0 / 60)
	check(game.carrier == actor, "guard collects a ball outside the normal pickup radius")
	var opponent = game.players[20]
	var ally = game.players[8]
	opponent.position = Vector3(4, 0, 0)
	ally.position = Vector3(0, 0, 4)
	game.carrier = opponent
	game.ball.position = Vector3(3, 0.34, 0)
	var normal_speed: float = opponent.move_speed()
	game.use_ability(actor)
	check(actor.ability_time == 5 and actor.ability_cooldown == 20, "slow field lasts 5s with 20s cooldown")
	check(not game.use_ability(actor), "repeat W cannot refresh field")
	var old_ball: Vector3 = game.ball.position
	game._apply_slow_fields()
	check(is_equal_approx(opponent.move_speed(), normal_speed * 0.7), "enemy in field is slowed by 30 percent")
	check(actor.slow_multiplier == 1 and ally.slow_multiplier == 1, "field leaves caster and allies unaffected")
	check(game.carrier == opponent and game.ball.position == old_ball and game.ball.velocity == Vector3.ZERO, "field no longer steals or attracts ball")
	opponent.position.x = Roles.SLOW_RADIUS + 0.1
	game._apply_slow_fields()
	check(is_equal_approx(opponent.move_speed(), normal_speed), "leaving field clears slow")
	opponent.position.x = 4
	ally.archetype = Roles.Kind.GUARD
	ally.position = Vector3(0, 0, 1)
	game.use_ability(ally)
	game._apply_slow_fields()
	check(opponent.slow_multiplier == 0.7, "overlapping fields do not stack")
	ally.ability_time = 0
	for i in range(301):
		actor.step(1.0 / 60, [])
	game._apply_slow_fields()
	check(opponent.slow_multiplier == 1 and actor.ability_cooldown > 14.9, "field expires after 5s while cooldown remains")
	ally.position = Vector3(-30, 0, 20)
	opponent.position = Vector3(1.2, 0, 0)
	game.carrier = opponent
	game.possession_lock = 0
	game._update_possession(1.0 / 60)
	check(game.carrier == actor and actor.stats.tackles == 1 and opponent.stats.turnovers == 1, "successful tackle records winner and dispossessed player")
	game._update_possession(1.0 / 60)
	check(actor.stats.tackles == 1, "possession protection prevents duplicate tackle counts")
	opponent.position = Vector3(30, 0, 20)
	game.carrier = null
	game.last_touch = opponent
	game.possession_lock = 0
	game.ball.position = Vector3(0.4, 0.34, 0)
	game.ball.velocity = Vector3.ZERO
	game._update_possession(1.0 / 60)
	check(game.carrier == actor and actor.stats.interceptions == 1 and actor.stats.tackles == 1, "loose opposing ball is interception, not tackle")
	actor.archetype = Roles.Kind.CHARGER
	actor.reset_position(true)
	actor.position = Vector3.ZERO
	actor.target = Vector3(20, 0, 0)
	actor.facing = Vector3.RIGHT
	opponent.position = Vector3(30, 0, 20)
	ally.position = Vector3(-30, 0, 20)
	game.carrier = actor
	game.possession_lock = 1
	game.ball.position = Vector3(1.05, 0.34, 0)
	check(is_equal_approx(actor.move_speed(), 7.8 * 0.9), "charger passive reduces running speed 10 percent")
	key_event(game, KEY_W, true)
	check(actor.charging and actor.position == Vector3.ZERO and actor.dash_remaining == 0, "W press starts charging without teleporting")
	for i in range(roundi(Roles.CHARGE_DURATION * 0.5 * 60)):
		actor.step(1.0 / 60, [])
		game._update_possession(1.0 / 60)
	key_event(game, KEY_W, true, true)
	check(actor.position.x > 1.0 and is_equal_approx(actor.charge_fraction(), 0.5), "holding W allows movement; repeat does not reset charge")
	check(game.carrier == actor and is_equal_approx(game.ball.position.x, actor.position.x + actor.control_distance()), "ball follows movement while charging")
	var release_position: Vector3 = actor.position
	key_event(game, KEY_W, false)
	var half_charge_distance: float = actor.dash_remaining
	check(not actor.charging and is_equal_approx(half_charge_distance, 6.0) and actor.position == release_position, "release starts distance-scaled dash without teleporting")
	check(actor.ability_cooldown == 4 and not game.use_ability(actor), "dash has one use and 4s cooldown from release")
	actor.step(0.1, [])
	game._update_possession(0.1)
	check(actor.position.x > release_position.x and actor.position.x < release_position.x + half_charge_distance, "dash travels over time")
	check(game.carrier == actor and is_equal_approx(game.ball.position.x, actor.position.x + actor.control_distance()), "ball stays at feet during dash")
	actor.target = Vector3(0, 0, 25)
	for i in range(60):
		actor.step(1.0 / 60, [])
		game._update_possession(1.0 / 60)
	check(is_equal_approx(actor.position.x, release_position.x + half_charge_distance) and is_zero_approx(actor.position.z), "dash direction is locked and stops at charged distance")
	var remaining: float = actor.ability_cooldown
	game.reset_kickoff(1)
	check(is_equal_approx(actor.ability_cooldown, remaining) and not game.use_ability(actor), "kickoff does not reset cooldown")
	for i in range(241):
		actor.step(1.0 / 60, [])
	check(game.use_ability(actor), "dash becomes ready after cooldown")
	actor.step(2.0, [])
	check(is_equal_approx(actor.charge_time, Roles.CHARGE_DURATION), "holding beyond configured maximum caps charge")
	game.release_ability(actor)
	check(is_equal_approx(actor.dash_remaining, Roles.DASH_MAX_DISTANCE) and actor.dash_remaining > half_charge_distance, "full charge dashes farther")
	actor.position = Vector3(47, 0, 0)
	actor.facing = Vector3.RIGHT
	actor.dash_direction = Vector3.RIGHT
	actor.step(0.1, [])
	check(is_equal_approx(actor.position.x, 48 - actor.collision_radius()) and actor.dash_remaining == 0, "dash stops at pitch boundary")
	actor.reset_position(true)
	game.use_ability(actor)
	game.release_ability(actor)
	check(is_equal_approx(actor.dash_remaining, Roles.DASH_MIN_DISTANCE), "tap W makes short dash")
	actor.reset_position(true)
	key_event(game, KEY_W, true)
	key_event(game, KEY_ESCAPE, true)
	key_event(game, KEY_W, false)
	key_event(game, KEY_ESCAPE, true)
	check(not actor.charging and actor.dash_remaining == 0 and actor.ability_cooldown == 0, "pause cancels charge without stuck or delayed dash")
	key_event(game, KEY_W, true)
	game._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	check(not actor.charging, "losing focus cancels charge")
	actor.human = false
	actor.reset_position(true)
	actor.position = Vector3.ZERO
	actor.target = Vector3(30, 0, 0)
	game.carrier = actor
	game.ball.position = Vector3(1.05, 0.34, 0)
	actor.ai_think_wait = 5.0
	game._try_ai_ability(actor, true)
	check(not actor.charging and actor.ai_skill_pending, "NPC schedules W instead of casting immediately")
	actor.step(0.2, [])
	game._update_ai(0.2)
	check(not actor.charging, "NPC cannot cast W before reaction delay")
	actor.step(actor.ai_skill_wait + 0.01, [])
	game._update_ai(0.01)
	check(actor.charging and actor.ai_charge_goal >= Roles.CHARGE_DURATION * Roles.AI_CHARGE_MIN_FRACTION and actor.dash_remaining == 0, "NPC respects minimum charge telegraph")
	actor.step(0.4, [])
	game._update_ai(0.4)
	check(actor.charging and game.carrier == actor and actor.position.x > 0, "NPC moves and keeps ball while charging")
	actor.step(0.81, [])
	game._update_ai(0.81)
	check(not actor.charging and actor.dash_remaining > 0 and game.carrier == actor, "NPC releases charged dash with ball")
	actor.human = true
	actor.reset_position(true)
	actor.archetype = Roles.Kind.RUNNER
	game.carrier = actor
	game.player_kick()
	check(game.carrier == null and game.ball.velocity.x > 28, "Q remains a forward kick")
	game.ball.position = Vector3(48.5, 0.34, 0)
	game._check_boundaries()
	check(game.goal_events.size() == 1 and game.goal_events[0].role == Roles.Kind.RUNNER and not game.goal_events[0].own_goal, "goal records the scoring role")
	game.ball.position = Vector3(-48.5, 0.34, 0)
	game._check_boundaries()
	check(game.goal_events.size() == 2 and game.goal_events[1].own_goal, "own goals are recorded separately")
	check(actor.stats.goals == 1 and actor.stats.own_goals == 1, "player statistics distinguish goals from own goals")
	check_ai_reactions(game)
	check_ai_role_casts(game)
	actor.human = false
	game.rng.seed = 8100
	game.start_match()
	game.reset_kickoff(0)
	for i in range(22):
		game.players[i].archetype = i % 3
	for i in range(1800):
		game._physics_process(1.0 / 60)
	var measured_time: float = game.loose_ball_seconds
	var tackles := 0
	var turnovers := 0
	for other in game.players:
		measured_time += other.stats.possession_seconds
		tackles += other.stats.tackles
		turnovers += other.stats.turnovers
	check(is_equal_approx(measured_time, game.MATCH_DURATION - game.time_left), "possession plus loose-ball time equals active match time")
	check(tackles == turnovers, "live match tackles reconcile with lost possessions (%d/%d)" % [tackles, turnovers])
	print("RESULT: %d checks, %d failures" % [checks, failures])
	game.free()
	quit(1 if failures else 0)


func check_ai_role_casts(game: Node) -> void:
	# Supply a valid opportunity rather than requiring a random short match to create one.
	for other in game.players:
		other.reset_position(true)
		other.position = Vector3(-35, 0, 22)
		other.ai_think_wait = 10.0
	var actor = game.player
	var opponent = game.players[20]
	opponent.position = Vector3(3, 0, 0)
	for kind in range(3):
		actor.reset_position(true)
		actor.human = false
		actor.archetype = kind
		actor.position = Vector3.ZERO
		actor.target = Vector3(25, 0, 0)
		actor.ai_think_wait = 10.0
		game.carrier = actor
		game.ball.position = Vector3(1, 0.34, 0)
		var before: int = game.ability_casts[kind]
		game._try_ai_ability(actor, true)
		var delayed: bool = actor.ai_skill_pending and actor.ai_skill_wait >= game.AI_SKILL_REACTION.x and game.ability_casts[kind] == before
		actor.step(actor.ai_skill_wait + 0.01, [])
		game._update_ai(0.01)
		if kind == Roles.Kind.CHARGER:
			actor.step(Roles.CHARGE_DURATION + 0.01, [])
			game._update_ai(0.01)
		check(delayed and game.ability_casts[kind] == before + 1 and actor.ability_cooldown > 0, "role %d NPC completes a real cast after reaction and charge delays" % kind)


func check_ai_reactions(game: Node) -> void:
	game.rng.seed = 20261020
	var actor = game.player
	var opponent = game.players[20]
	for other in game.players:
		other.reset_position(true)
		other.position = Vector3(-35, 0, 22)
		other.ai_think_wait = 10.0
	actor.position = Vector3.ZERO
	actor.target = Vector3(20, 0, 0)
	actor.human = false
	opponent.position = Vector3(1.1, 0, 0)
	game.carrier = opponent
	game.possession_lock = 0.0
	game._update_possession(1.0 / 60)
	check(game.carrier == opponent and actor.ai_tackle_target == opponent, "NPC contact starts a delayed tackle")
	var first_wait: float = actor.ai_tackle_wait
	game._update_possession(0.2)
	check(game.carrier == opponent and actor.ai_tackle_wait < first_wait, "NPC cannot tackle during reaction delay")
	opponent.position = Vector3(5, 0, 0)
	game._update_possession(1.0 / 60)
	check(actor.ai_tackle_target == null, "escaping tackle range cancels pending steal")
	opponent.position = Vector3(1.1, 0, 0)
	game._update_possession(1.0 / 60)
	var replacement = game.players[21]
	replacement.position = opponent.position
	opponent.position = Vector3(5, 0, 0)
	game.carrier = replacement
	game._update_possession(1.0 / 60)
	check(game.carrier == replacement and actor.ai_tackle_target == replacement and actor.ai_tackle_wait >= game.AI_TACKLE_REACTION.x, "new carrier requires a fresh tackle reaction")
	game._update_possession(actor.ai_tackle_wait + 0.01)
	check(game.carrier == actor and actor.stats.tackles == 1 and replacement.stats.turnovers == 1, "NPC completes delayed tackle and records statistics")
	actor.human = true
	game.carrier = replacement
	game.possession_lock = 0.0
	game._update_possession(1.0 / 60)
	check(game.carrier == actor and actor.stats.tackles == 2, "human tackle stays responsive")
	for kind in range(3):
		actor.archetype = kind
		actor.human = true
		var human_speed: float = actor.move_speed()
		actor.human = false
		check(is_equal_approx(human_speed, actor.move_speed()), "role %d NPC and human running speeds match" % kind)
		actor.goalkeeper = true
		check(is_equal_approx(human_speed, actor.move_speed()), "role %d goalkeeper also uses the same running speed" % kind)
		actor.goalkeeper = false
	actor.archetype = Roles.Kind.RUNNER
	actor.ai_think_wait = 0.35
	game.carrier = null
	game.ball.position = Vector3(5, 0.34, 0)
	var old_target: Vector3 = actor.target
	for i in range(12):
		game._update_ai(1.0 / 60)
	check(actor.target == old_target, "NPC does not replan movement every frame")
	for i in range(12):
		game._update_ai(1.0 / 60)
	check(actor.target != old_target, "NPC updates movement after think interval")
	actor.ai_think_wait = 10.0
	actor.ai_skill_pending = false
	actor.ai_skill_wait = 0.0
	actor.target = Vector3(20, 0, 0)
	game._try_ai_ability(actor, true)
	game.ball.position = Vector3(-40, 0.34, 0)
	actor.step(actor.ai_skill_wait + 0.01, [])
	game._update_ai(0.01)
	check(not actor.ai_skill_pending and actor.ability_time == 0, "expired skill opportunity cancels instead of casting blindly")
	actor.position = Vector3.ZERO
	actor.facing = Vector3.LEFT
	game.carrier = actor
	actor.ai_think_wait = 10.0
	game._queue_ai_kick(actor, Vector3.RIGHT, 27.0, game.AI_SHOT_ERROR)
	var aim: Vector3 = actor.ai_aim_direction
	game._update_ai(1.0 / 60)
	actor.step(1.0 / 60, [])
	check(game.carrier == actor and actor.facing.x < -0.9, "NPC turns before shooting instead of snapping 180 degrees")
	check(actor.ai_aim_direction == aim, "aim error stays fixed while executing the shot")
	for i in range(120):
		actor.step(1.0 / 60, [])
		game._update_ai(1.0 / 60)
		if game.carrier == null:
			break
	var shot_direction := Vector3(game.ball.velocity.x, 0, game.ball.velocity.z).normalized()
	check(game.carrier == null and shot_direction.is_equal_approx(actor.facing), "NPC kicks along its actual facing after turning")
	check(aim.angle_to(Vector3.RIGHT) <= deg_to_rad(game.AI_SHOT_ERROR) + 0.001 and aim.angle_to(Vector3.RIGHT) > 0.001, "shot has bounded nonzero random aim error")
	game.carrier = actor
	game._queue_ai_kick(actor, Vector3.RIGHT, 18.0, game.AI_PASS_ERROR)
	check(actor.ai_aim_direction.angle_to(Vector3.RIGHT) <= deg_to_rad(game.AI_PASS_ERROR) + 0.001, "pass uses its own bounded aim error")
	game.carrier = opponent
	game._update_ai(1.0 / 60)
	check(actor.ai_kick_power == 0.0 and game.carrier == opponent, "losing possession cancels the queued kick")
	actor.ai_skill_pending = true
	actor.ai_tackle_target = opponent
	game.reset_kickoff(0)
	check(not actor.ai_skill_pending and actor.ai_tackle_target == null and actor.ai_kick_power == 0.0 and actor.ai_think_wait > 0.0, "kickoff clears pending AI actions and staggers thinking")
