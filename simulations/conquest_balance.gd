extends SceneTree
## Legal automated player inputs; this samples scenarios, not human win rates.
const Modes = preload("res://scripts/game_modes.gd")
var chapter := 0
var revision := "baseline"
var only: Array[int] = []
var first_variant := 0
var variant_count := 3
var trial_seconds := 0


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--chapter="):
			chapter = int(arg.get_slice("=", 1))
		elif arg.begins_with("--revision="):
			revision = arg.get_slice("=", 1)
		elif arg.begins_with("--variant-start="):
			first_variant = int(arg.get_slice("=", 1))
		elif arg.begins_with("--variant-count="):
			variant_count = int(arg.get_slice("=", 1))
		elif arg.begins_with("--seconds="):
			trial_seconds = int(arg.get_slice("=", 1))
		elif arg.begins_with("--levels="):
			for value in arg.get_slice("=", 1).split(","):
				only.append(int(value) - 1)
	call_deferred("run")


func aim_kick(game: Node, point: Vector3) -> void:
	# Left click aims instantly in the real input handler; Q retains its fixed power/CD.
	if game.player.action_blocked() or game.player.kick_cooldown > 0:
		return
	var direction: Vector3 = point - game.player.position
	direction.y = 0.0
	game.player.target = game.player.position
	game.player.velocity = Vector3.ZERO
	game.player.facing = direction.normalized()
	game.player_kick()


func control(game: Node, variant: int) -> void:
	var actor = game.player
	var ball: Vector3 = game.ball.position
	ball.y = 0.0
	var aim := Vector3(52, 0, -2.8 if variant % 2 == 0 else 2.8)
	var pressure: float = game.tactics.pressure(actor)
	if actor.goalkeeper:
		actor.target = actor.constrain_position(Vector3(-48, 0, clampf(ball.z * 0.3, -5, 5)))
		if ball.x < -37 and ball.distance_to(actor.position) < 12:
			actor.target = actor.constrain_position(ball)
		if game.carrier == actor:
			var mate = game.tactics.pass_target(actor)
			aim_kick(game, mate.position + mate.velocity * 0.3 if mate != null else Vector3(-20, 0, 24 if ball.z >= 0 else -24))
		elif game.carrier == null and ball.distance_to(actor.position) < 8:
			aim_kick(game, ball)
	elif game.carrier == actor:
		actor.target = actor.constrain_position(Vector3(48, 0, actor.position.z * 0.65))
		if actor.position.x > 27 and absf(actor.position.z) < 18:
			aim_kick(game, aim)
		elif pressure < 5.0:
			var mate = game.tactics.pass_target(actor)
			if mate != null:
				aim_kick(game, mate.position + mate.velocity * 0.3)
	elif game.carrier != null and game.carrier.team == 0:
		actor.target = actor.constrain_position(game.tactics.support(actor))
	else:
		actor.target = actor.constrain_position(ball + Vector3(game.ball.velocity.x, 0, game.ball.velocity.z) * 0.15)
		if actor.position.distance_to(ball) < 1.8 and ball.x > 28:
			aim_kick(game, aim)
	if actor.charging and actor.charge_time >= minf(0.55, actor.max_charge_time()):
		game.release_ability(actor)
	elif game._ai_wants_ability(actor, true):
		game.use_ability(actor, actor.facing, ball)
	if game._ai_wants_e(actor):
		game.use_e(actor, actor.target)


func run() -> void:
	var output := "res://work/conquest-balance/" + revision + "/"
	DirAccess.make_dir_recursive_absolute(output)
	var levels: Array[int] = only
	if levels.is_empty():
		for level in range(chapter * 5, chapter * 5 + 5):
			levels.append(level)
	for level in levels:
		for variant in range(first_variant, first_variant + variant_count):
			var path := output + "%02d-%d.json" % [level + 1, variant + 1]
			assert(not FileAccess.file_exists(path), "Do not overwrite completed trials")
			var game = load("res://main.tscn").instantiate()
			game.simulation_mode = true
			game.mode = "conquest"
			game.challenge_id = level
			root.add_child(game)
			game.set_physics_process(false)
			var rules: Dictionary = Modes.CHALLENGES[level].duplicate(true)
			game.choose_role(rules.role if rules.role >= 0 else [0, 2, 1][variant % 3])
			game.start_match()
			if trial_seconds > 0:
				rules.seconds = trial_seconds
				game.regulation_duration = float(trial_seconds)
				game.time_left = float(trial_seconds)
			game.player.human = true
			var formation: int = [1, 0, 4, 2, 1, 0][variant]
			game.team_formations[0] = formation
			game.rng.seed = rules.seed + variant * 101
			for team in range(2):
				game.assign_formation(team, true)
			for actor in game.players:
				actor.build_variant = variant % 3
			var ticks := 0
			while not game.finished:
				if game.shop_open:
					game.choose_formation(formation)
					game.player.human = false
					game._npc_shop()
					game.npc_shopped = true
					game.player.human = true
					game.skip_shop()
				if ticks % 12 == 0:
					control(game, variant)
				game._physics_process(1.0 / 60.0)
				ticks += 1
			var file := FileAccess.open(path, FileAccess.WRITE)
			file.store_string(JSON.stringify({"level": level + 1, "rules": rules, "variant": variant,
				"hero": game.player.archetype, "formation": formation, "won": game.result_won,
				"score": game.score, "seconds": game.match_elapsed(), "player": game.player.stats,
				"goals": game.goal_events, "passes": game.tactics.pass_events.size(),
				"e_casts": game.e_cast_events.size(), "purchases": game.purchase_events.size()}, "\t"))
			file.close()
			print("LEVEL %02d / variant %d: %s %d:%d %.1fs / player goals %d" % [level + 1, variant + 1,
				"WIN" if game.result_won else "LOSS", game.score[0], game.score[1], game.match_elapsed(), game.player.stats.goals])
			game.free()
			await process_frame
	print("CONQUEST TRIALS COMPLETE " + revision)
	quit()
