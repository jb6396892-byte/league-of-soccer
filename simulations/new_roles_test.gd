extends SceneTree
const Roles = preload("res://scripts/archetypes.gd")
var checks := 0
var failures := 0
var game: Node


func _initialize() -> void:
	call_deferred("run")


func check(ok: bool, message: String) -> void:
	checks += 1
	if ok:
		print("PASS: " + message)
	else:
		failures += 1
		printerr("FAIL: " + message)


func press(key: Key) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = key
	event.pressed = true
	game._unhandled_input(event)


func isolate() -> void:
	game._clear_projectiles()
	for actor in game.players:
		actor.reset_position(true)
		actor.position = Vector3(20, 0, 26)
		actor.target = actor.position
		actor.ai_think_wait = 100.0
	game.carrier = null
	game.possession_lock = 0.0


func run() -> void:
	game = load("res://main.tscn").instantiate()
	game.simulation_mode = true
	root.add_child(game)
	game.set_physics_process(false)
	game.rng.seed = 10021
	game.start_match()
	check(game.players.filter(func(a): return a.archetype == Roles.Kind.KEEPER).size() == 2, "one specialist keeper per team")
	press(KEY_ENTER)
	check(not game.shop_open and game.goal_pause == 0, "Enter immediately ends shopping")
	check(game.players.all(func(a): return not a.inventory.is_empty() and a.gold >= 0), "immediate skip still lets all NPCs purchase affordable components")
	game.open_shop(1, "test")
	game.paused = true
	press(KEY_ENTER)
	check(game.shop_open, "Enter respects pause")
	game.paused = false
	press(KEY_ENTER)
	check(game.carrier.team == 1 and not game.shop_open, "skip preserves the next kickoff team")
	game.choose_role(Roles.Kind.KEEPER)
	check(game.player == game.players[0] and game.player.archetype == Roles.Kind.KEEPER, "selecting keeper controls blue number 1")
	game.skip_shop()
	check(not game.carrier.goalkeeper and game.carrier.tactical_line == game.Formations.Line.FRONT and game.player.position.x < -32, "keeper stays in its box while a formation forward takes kickoff")
	game.choose_role(Roles.Kind.STRIKER)
	game.skip_shop()
	check(game.player == game.players[9] and game.players[0].archetype == Roles.Kind.KEEPER, "switching back keeps exactly the same keeper")
	isolate()
	var actor = game.player
	actor.human = true
	actor.archetype = Roles.Kind.STRIKER
	actor.position = Vector3.ZERO
	actor.target = Vector3(12, 0, 0)
	check(is_equal_approx(actor.move_speed(), 7.8 * 0.95), "striker starts 5 percent slower")
	game.last_touch = actor
	game.ball.position = Vector3(48.5, 0.34, 0)
	game._check_boundaries()
	check(is_equal_approx(actor.move_speed(), 7.8 * 0.95), "scoring no longer increases flag movement speed")
	game.skip_shop()
	check(actor.stats.goals == 1 and is_equal_approx(actor.move_speed(), 7.8 * 0.95), "kickoff preserves goals without the removed speed passive")
	game.last_touch = game.players[8]
	game.ball.position = Vector3(48.5, 0.34, 0)
	game._check_boundaries()
	check(actor.stats.goals == 1, "teammate goal gives no speed stack")
	game.skip_shop()
	game.last_touch = actor
	game.ball.position = Vector3(-48.5, 0.34, 0)
	game._check_boundaries()
	check(actor.stats.goals == 1, "own goal gives no speed stack")
	game.skip_shop()
	isolate()
	actor.position = Vector3.ZERO
	actor.target = Vector3(12, 0, 0)
	var enemy = game.players[20]
	enemy.position = Vector3(6, 0, 0)
	var ally = game.players[8]
	ally.position = Vector3(3, 0, 0)
	check(game.use_ability(actor, Vector3.RIGHT), "striker starts aimed throw")
	check(game.projectiles.size() == 1 and actor.ability_cooldown == Roles.COOLDOWN[3], "throw creates warning and starts cooldown")
	game._update_projectiles(0.49)
	actor.step(0.49, [])
	check(enemy.stun_time == 0 and actor.position.x > 0, "initial windup moves but cannot hit before launch")
	check(not game.use_ability(actor), "throw cannot be repeatedly restarted")
	game._update_projectiles(0.02)
	check(enemy.stun_time == 0, "warning expiry launches rather than instantly hitting")
	game._update_projectiles(0.30)
	check(enemy.stun_time == 1 and actor.stats.stuns == 1 and ally.stun_time == 0, "travelling shot crosses allies and stuns first enemy")
	check(actor.gold == 520 and actor.stats.gold_earned == 20, "one confirmed stun grants twenty gold")
	check(game.projectiles.is_empty(), "first hit consumes projectile")
	enemy.target = Vector3(15, 0, 0)
	var stunned_at: Vector3 = enemy.position
	enemy.step(0.3, [])
	check(enemy.position == stunned_at and not game.use_ability(enemy), "stun blocks movement and W")
	game.player = enemy
	enemy.kick_cooldown = 0.0
	game.carrier = enemy
	game.player_kick()
	check(game.carrier == enemy, "stun blocks Q")
	game.player = actor
	game.carrier = actor
	enemy.position = actor.position + Vector3.RIGHT
	enemy.human = true
	game.possession_lock = 0
	game._try_tackle(0.01)
	check(game.carrier == actor, "stun blocks contact tackle")
	enemy.step(0.8, [])
	check(enemy.stun_time == 0 and enemy.position != stunned_at, "stun expires and movement resumes")
	actor.throw_windup = 0
	actor.ability_cooldown = 0
	enemy.position = Vector3(6, 0, 4)
	game.use_ability(actor, Vector3.RIGHT)
	game._update_projectiles(0.51)
	game._update_projectiles(2.0)
	check(enemy.stun_time == 0 and game.projectiles.is_empty(), "off-path opponent dodges and projectile expires")
	actor.ability_cooldown = 0
	actor.throw_windup = 0
	game.use_ability(actor, Vector3.RIGHT)
	actor.stun_time = 1
	game._update_projectiles(0.1)
	check(game.projectiles.is_empty() and actor.throw_windup == 0, "stun interrupts an unfinished throw")
	isolate()
	var keeper = game.players[0]
	keeper.position = Vector3(-40, 0, 0)
	keeper.target = Vector3(10, 0, 25)
	keeper.human = true
	for i in range(180):
		keeper.step(1.0 / 60, [])
	check(keeper.position.x <= -32 - keeper.collision_radius() + 0.00001 and keeper.position.z <= 16 - keeper.collision_radius() + 0.00001, "blue keeper cannot leave own penalty area")
	var red_keeper = game.players[11]
	red_keeper.position = Vector3(40, 0, 0)
	red_keeper.target = Vector3(-10, 0, -25)
	for i in range(180):
		red_keeper.step(1.0 / 60, [])
	check(red_keeper.position.x >= 32 + red_keeper.collision_radius() - 0.00001 and red_keeper.position.z >= -16 + red_keeper.collision_radius() - 0.00001, "red keeper has mirrored penalty constraint")
	keeper.position = Vector3(-42, 0, 0)
	keeper.facing = Vector3.RIGHT
	game.last_touch = enemy
	game.ball.position = Vector3(-39.5, 2.9, 0)
	game.ball.velocity = Vector3(-12, 0, 0)
	check(game.keeper_save(keeper), "keeper Q opens hand-save window")
	game._update_possession(0.01)
	check(game.carrier == keeper and keeper.stats.saves == 1, "expanded hand save catches high ball beyond ordinary pickup")
	check(not game.keeper_save(keeper), "hand save has cooldown")
	keeper.kick_cooldown = 0
	game.player = keeper
	game.player_kick()
	check(game.carrier == null and game.ball.velocity.x > 28, "keeper Q with possession throws ball forward")
	game.last_touch = enemy
	game.possession_lock = 0
	keeper.save_time = 0
	game.ball.position = keeper.position + Vector3(1, 0.34, 0)
	game.ball.velocity = Vector3(-30, 0, 0)
	game._update_possession(0.01)
	check(game.carrier == null and game.ball.velocity.length() < 19, "without Q fast shot rebounds instead of automatic hand catch")
	game.player = actor
	enemy.position = keeper.position + Vector3(5, 0, 0)
	var behind = game.players[21]
	behind.position = keeper.position + Vector3(-3, 0, 0)
	ally.position = keeper.position + Vector3(4, 0, 0)
	game.use_ability(keeper)
	game._apply_slow_fields()
	check(keeper.ability_time == 5 and keeper.ability_cooldown == Roles.COOLDOWN[4], "keeper W lasts five seconds and uses configured cooldown")
	check(is_equal_approx(enemy.slow_multiplier, 0.8) and behind.slow_multiplier == 1 and ally.slow_multiplier == 1, "cone only slows enemies ahead by twenty percent")
	actor.archetype = Roles.Kind.GUARD
	actor.position = enemy.position
	actor.stun_time = 0
	game.use_ability(actor)
	game._apply_slow_fields()
	check(enemy.slow_multiplier == 0.7, "overlapping keeper and hedgehog fields use stronger slow only")
	enemy.inventory.append(6)
	game._apply_slow_fields()
	check(is_equal_approx(enemy.slow_multiplier, 0.82), "resistance gear reduces strongest slow")
	isolate()
	keeper.position = Vector3(-42, 0, 0)
	keeper.target = keeper.position
	keeper.human = false
	keeper.ai_think_wait = 0
	game.ball.position = Vector3(-36, 0.34, 0)
	game.ball.velocity = Vector3(-20, 0, 0)
	game._update_ai(0.01)
	check(keeper.ai_save_wait >= game.AI_SKILL_REACTION.x and keeper.save_time == 0, "NPC keeper schedules human-like reaction before saving")
	game.open_shop(0, "reset")
	check(game.projectiles.is_empty() and keeper.save_time == 0, "shopping clears active combat effects")
	game.choose_role(Roles.Kind.STRIKER)
	check(game.player.stats.goals == 0 and is_equal_approx(game.player.move_speed(), 7.8 * 0.95), "new match resets scorer growth")
	print("RESULT: %d checks, %d failures" % [checks, failures])
	game.free()
	quit(1 if failures else 0)
