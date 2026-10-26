extends SceneTree
const Settings = preload("res://scripts/match_settings.gd")
var checks := 0
var failures := 0


func _initialize() -> void:
	call_deferred("run")


func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
	print(("PASS: " if ok else "FAIL: ") + message)


func run() -> void:
	var game = load("res://main.tscn").instantiate()
	game.simulation_mode = true
	root.add_child(game)
	game.set_physics_process(false)
	check(game.match_minutes == 5 and game.difficulty == 1 and game.ally_difficulty == 1, "defaults remain five minutes and normal for both sides")
	for minutes in range(5, 16):
		check(game.choose_minutes(minutes) and game.time_left == minutes * 60 and game.match_elapsed() == 0, "pregame duration %d updates clock" % minutes)
	check(not game.choose_minutes(4) and not game.choose_minutes(16) and game.match_minutes == 15, "invalid durations leave configuration intact")
	var actor = game.player
	var enemy = game.players[20]
	actor.archetype = 0
	enemy.archetype = 0
	for difficulty in range(3):
		check(game.choose_difficulty(difficulty), "choose difficulty %d" % difficulty)
		check(game.ai_profile(actor) == Settings.PROFILES[1] and game.ai_profile(enemy) == Settings.PROFILES[difficulty], "only opposing NPC profile changes")
		check(is_equal_approx(actor.move_speed(), enemy.move_speed()), "difficulty does not alter physical speed")
		for key in ["think", "skill", "tackle"]:
			var interval: Vector2 = Settings.PROFILES[difficulty][key]
			var delay: float = game.ai_delay(enemy, key)
			check(delay >= interval.x and delay <= interval.y, "configured %s delay is applied" % key)
	check(not game.choose_difficulty(-1) and not game.choose_difficulty(3), "invalid difficulties rejected")
	for ally in range(3):
		check(game.choose_ally_difficulty(ally), "choose allied difficulty %d" % ally)
		for opponent in range(3):
			game.choose_difficulty(opponent)
			check(game.ai_profile(actor) == Settings.PROFILES[ally] and game.ai_profile(enemy) == Settings.PROFILES[opponent], "both profiles remain independent for combination %d/%d" % [ally, opponent])
		for key in ["think", "skill", "tackle"]:
			var interval: Vector2 = Settings.PROFILES[ally][key]
			var delay: float = game.ai_delay(actor, key)
			check(delay >= interval.x and delay <= interval.y, "allied %s delay follows chosen difficulty" % key)
	check(not game.choose_ally_difficulty(-1) and not game.choose_ally_difficulty(3) and game.ally_difficulty == 2, "invalid allied difficulty leaves choice intact")
	for fixed_mode in ["conquest", "rogue", "training", "tutorial"]:
		game.mode = fixed_mode
		check(not game.choose_ally_difficulty(0) and game.ai_difficulty(0) == (2 if fixed_mode == "rogue" else 1), "free choice cannot override %s teammates" % fixed_mode)
	game.mode = "free"
	game.choose_difficulty(1)
	game.start_match()
	check(game.time_left == 900 and game.regulation_duration == 900, "fifteen minute selection starts full match")
	check(not game.choose_minutes(5) and not game.choose_difficulty(2) and not game.choose_ally_difficulty(0), "active match cannot silently change settings")
	game.skip_shop()
	game.time_left = 855
	check(game.match_elapsed() == 45, "elapsed clock uses selected regulation duration")
	game.score = [0, 0]
	game.time_left = 0.01
	game.supply_clock = 89.99
	game._physics_process(0.02)
	check(game.overtime_count == 1 and game.time_left == 120 and game.match_elapsed() == 900, "fifteen minute tie enters full overtime with continuous clock")
	check(game.supply_clock < 0.01 and not game.shop_open and game.timeout_tokens == [2, 2], "coincident overtime grants a token without opening a shop")
	game._physics_process(game.goal_pause + 0.01)
	game.score = [1, 0]
	game.time_left = 0.01
	game._physics_process(0.02)
	check(game.finished and game.match_elapsed() == 1020, "overtime winner ends selected-duration game")
	game.start_match()
	check(game.time_left == 900 and game.difficulty == 1 and game.ai_difficulty(0) == 2 and game.overtime_count == 0, "restart retains both difficulty choices and clears overtime")
	game.skip_shop()
	actor.human = true
	actor.position = Vector3(12, 0, 0)
	actor.velocity = Vector3.RIGHT
	game.carrier = actor
	for p in game.players:
		if p != actor:
			p.position = Vector3(-40, 0, 28)
	enemy.position = Vector3(17, 0, 3)
	for difficulty in range(3):
		game.difficulty = difficulty
		check(game.chaser_count(1) == 1 and game.chaser_count(0) == 1, "one direct challenger leaves teammates available for cover at every difficulty")
		var targets := {}
		game._add_player_coverage(targets)
		check(targets.has(enemy) == (difficulty == 2), "hard mode adds nearby player passing-lane cover")
	game.player.human = false
	var targets := {}
	game._add_player_coverage(targets)
	check(targets.is_empty(), "targeted player cover requires an actual human")
	game.started = false
	game.finished = false
	game.choose_minutes(5)
	game.choose_difficulty(1)
	game.start_match()
	check(game.time_left == 300 and game.ai_profile(enemy).think == game.AI_THINK_INTERVAL and game.ai_profile(enemy).skill == game.AI_SKILL_REACTION and game.ai_profile(enemy).tackle == game.AI_TACKLE_REACTION, "normal keeps previous timings and five-minute behavior")
	game.skip_shop()
	check(game.timeout_tokens == [1, 1], "each team begins with one shared timeout")
	game.supply_clock = 90.0 - 1.0 / 60.0
	game._physics_process(1.0 / 60.0)
	check(not game.shop_open and game.timeout_tokens == [2, 2], "ninety active seconds grants tokens without interrupting play")
	game.supply_clock = 90.0 - 1.0 / 60.0
	game._physics_process(1.0 / 60.0)
	check(game.timeout_tokens == [2, 2], "timeout storage is capped at two")
	game.carrier = null
	check(not game.request_timeout(0) and game.timeout_tokens[0] == 2, "loose ball cannot be used to request timeout")
	game.carrier = actor
	actor.position = Vector3(15, 0, 3)
	check(not game.request_timeout(1) and game.timeout_tokens[1] == 2, "opponent cannot stop a team in possession")
	check(game.request_timeout(0) and game.timeout_tokens == [1, 2] and game.timeout_team == 0, "possession owner spends exactly one token")
	check(not game.request_timeout(0) and game.timeout_tokens[0] == 1, "repeated request during the same shop cannot consume more tokens")
	var saved_time: float = game.time_left
	var saved_supply: float = game.supply_clock
	actor.ability_cooldown = 20.0
	game._physics_process(1.0)
	check(game.time_left == saved_time and game.supply_clock == saved_supply and actor.ability_cooldown == 20.0, "timeout freezes match, replenishment and skill clocks")
	game.skip_shop()
	check(not game.shop_open and game.carrier.team == 0 and game.carrier.position.distance_to(Vector3.ZERO) < 2.0, "early close gives the requesting team a centre kickoff")
	game.carrier = enemy
	check(game.request_timeout(1), "red team can also request a timeout with possession")
	game._physics_process(15.0)
	check(not game.shop_open and game.carrier.team == 1 and game.time_left == saved_time, "fifteen seconds automatically ends timeout with red centre kickoff")
	game.timeout_tokens[1] = 0
	check(not game.request_timeout(1), "no token means no shop")
	game.start_match()
	check(game.supply_clock == 0.0 and game.timeout_tokens == [1, 1], "fresh match resets shared token supply")
	game.skip_shop()
	game.carrier = null
	game.last_touch = actor
	game.ball.position = Vector3(49, 0.34, 0)
	game.ball.velocity = Vector3.ZERO
	game.supply_clock = 90.0 - 1.0 / 60.0
	game._physics_process(1.0 / 60.0)
	check(not game.shop_open and game.score == [1, 0] and game.timeout_tokens == [2, 2] and game.kickoff_team == 1, "coincident goal and token grant gives conceding side kickoff without a shop")
	game._physics_process(game.goal_pause + 0.01)
	game.time_left = 200
	for p in game.players:
		p.human = false
		p.gold = 1000
		p.position = Vector3(-35 if p.team == 0 else 30, 0, 15)
	game.carrier = enemy
	game.possession_lock = 0
	game.timeout_ai_wait = 0
	game._try_ai_timeout(0.1)
	check(game.shop_open and game.timeout_team == 1 and game.timeout_events.back().ai, "computer team uses a shared timeout from safe possession when purchases are affordable")
	print("RESULT: %d checks, %d failures" % [checks, failures])
	game.free()
	quit(1 if failures else 0)
