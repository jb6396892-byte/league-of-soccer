extends SceneTree
var game: Node3D
var checks := 0
var failures := 0


func _initialize() -> void:
	call_deferred("run")


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
	print(("PASS: " if ok else "FAIL: ") + label)


func advance(seconds: float) -> void:
	for frame in range(roundi(seconds * 60)):
		game._physics_process(1.0 / 60)


func setup() -> void:
	game.rng.seed = 78201
	game.difficulty = 2
	game.start_match()
	game.skip_shop()
	game.tactics.reset(true)
	game.carrier = null
	game.possession_lock = 0
	for i in range(22):
		var actor = game.players[i]
		actor.human = true
		actor.position = Vector3(-25 + i * 2, 0, 26)
		actor.target = actor.position
		actor.velocity = Vector3.ZERO
		actor.inventory.clear()
	var keeper = game.players[0]
	keeper.position = Vector3(-43, 0, 0)
	keeper.target = keeper.position
	keeper.facing = Vector3.RIGHT
	keeper.human = false
	keeper.ai_think_wait = 0.4
	game.last_touch = game.players[15]
	game.ball.position = Vector3(-39, 1.5, 0)
	game.ball.velocity = Vector3(-24, 0, 0)
	game.keeper_save(keeper)


func run() -> void:
	game = load("res://main.tscn").instantiate()
	game.simulation_mode = true
	root.add_child(game)
	game.set_physics_process(false)
	for outlet in [true, false]:
		for backwards in [false, true]:
			setup()
			var keeper = game.players[0]
			if backwards:
				keeper.facing = Vector3.LEFT
			if outlet:
				var mate = game.players[6]
				mate.position = Vector3(-28, 0, 9)
				mate.target = mate.position
				mate.human = false
			advance(0.1)
			check(game.carrier == keeper and keeper.stats.saves == 1, "real high-speed shot caught; outlet %s / back-facing %s" % [outlet, backwards])
			check(keeper.kick_cooldown <= 0.2 and keeper.save_time == 0, "catch ends the save animation and switches to distribution recovery")
			advance(1.3)
			var event: Dictionary = game.tactics.keeper_events[0]
			check(event.result == "released" and event.seconds < 1.25, "keeper actually releases within 1.25 seconds (%.2f)" % event.seconds)
			check(event.kind == ("keeper_outlet" if outlet else "keeper_clear"), "safe outlet or emergency clearance chosen")
	setup()
	var keeper = game.players[0]
	var presser = game.players[15]
	presser.human = false
	presser.position = Vector3(-39.8, 0, 0)
	presser.target = keeper.position
	advance(1.2)
	check(game.tactics.keeper_events[0].result == "released" and keeper.stats.turnovers == 0, "hard forward pressure does not steal the caught ball before release")
	check(game.ball.position.x > -38, "clearance travels out of the immediate danger area")
	setup()
	keeper = game.players[0]
	keeper.inventory.assign([11, 19, 4, 16])
	var mate = game.players[6]
	mate.position = Vector3(-27, 0, 8)
	mate.target = mate.position
	mate.human = false
	advance(1.2)
	check(game.tactics.keeper_events.size() == 1 and game.tactics.keeper_events[0].result == "released", "large pickup build does not recapture its own real distribution")
	check(game.tactics.pass_events[0].result == "complete", "large pickup build delivers the ball to its teammate")
	setup()
	advance(0.1)
	keeper = game.players[0]
	game.kick_ball(keeper, Vector3.RIGHT, 18)
	game.possession_lock = 0
	game.ball.position = keeper.position + Vector3(1.2, 0.34, 0)
	game.ball.velocity = Vector3.ZERO
	game.players[15].position = keeper.position + Vector3(1.5, 0, 0)
	game._update_possession(1.0 / 60)
	check(game.carrier == game.players[15], "opponent can still intercept a released keeper ball")
	setup()
	advance(0.1)
	var held: float = game.tactics.keeper_events[0].seconds
	var cool: float = game.players[0].kick_cooldown
	game.open_shop(0, "Supply", true)
	advance(3.0)
	check(game.tactics.keeper_events[0].seconds == held and game.players[0].kick_cooldown == cool, "supply pauses keeper hold and distribution timers")
	game.skip_shop()
	advance(1.2)
	check(game.tactics.keeper_events[0].result == "released", "keeper resumes distribution after supply")
	setup()
	advance(0.1)
	keeper = game.players[0]
	keeper.human = true
	game.player = keeper
	advance(0.21)
	game.player_kick()
	check(game.carrier == null and game.ball.velocity.x > 28, "human keeper can Q distribute after the same short recovery")
	setup()
	game.ball.position = Vector3(-30, 3, 15)
	game.ball.velocity = Vector3.ZERO
	advance(0.4)
	check(game.players[0].kick_cooldown > 1.0, "missed saves retain their full cooldown")
	setup()
	keeper = game.players[0]
	keeper.position = Vector3(-46, 0, 0)
	game.ball.position = Vector3(-48.5, 1.0, 0)
	game.ball.velocity = Vector3.ZERO
	game._update_possession(1.0 / 60)
	check(game.carrier == null and keeper.stats.saves == 0, "ball already over the goal line cannot become a phantom save")
	game._check_boundaries()
	check(game.score == [0, 1] and keeper.stats.own_goals == 0 and game.goal_events[0].role != 4, "over-line shot credited to shooter rather than keeper own goal")
	game.free()
	print("KEEPER: %d checks / %d failures" % [checks, failures])
	quit(1 if failures else 0)
