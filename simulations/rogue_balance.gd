extends SceneTree
const Run = preload("res://scripts/rogue_run.gd")
var rows: Array = []

func _initialize() -> void:
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



func choose_reward(expedition: RefCounted, variant: int) -> Dictionary:
	var best := 0
	var rating := -INF
	for i in range(expedition.offers.size()):
		var offer: Dictionary = expedition.offers[i]
		var value := float(offer.quality) * 1.5
		if offer.type == "recruit":
			value += 8.0 if variant % 3 != 2 else 5.0
		elif offer.type in ["w", "e"]:
			value += 6.0
		elif offer.type == "crown":
			value += {"captain": 8, "ace": 7, "fortress": 5, "engine": 6, "guardian": 4, "cannon": 6}[offer.value]
		elif offer.value in ["pace", "runner", "finisher", "power", "team_haste", "team_reach"]:
			value += 4.0
		if value > rating:
			rating = value
			best = i
	var selected: Dictionary = expedition.offers[best].duplicate(true)
	expedition.choose(best)
	return selected


func run() -> void:
	var round_id := 1
	var revision := ""
	var requested_seed := 0
	var requested_line := 0
	var ascension := 0
	var checkpoint_path := ""
	var elite_trial: Array[float] = []
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--round="):
			round_id = int(arg.get_slice("=", 1))
		elif arg.begins_with("--revision="):
			revision = arg.get_slice("=", 1)
		elif arg.begins_with("--seed="):
			requested_seed = int(arg.get_slice("=", 1))
		elif arg.begins_with("--line="):
			requested_line = int(arg.get_slice("=", 1))
		elif arg.begins_with("--ascension="):
			ascension = int(arg.get_slice("=", 1))
		elif arg.begins_with("--checkpoint="):
			checkpoint_path = arg.get_slice("=", 1)
		elif arg.begins_with("--elite="):
			for number in arg.get_slice("=", 1).split(","):
				elite_trial.append(float(number))
	var path := "res://work/rogue-v2-round-%d.json" % round_id
	if not revision.is_empty():
		DirAccess.make_dir_recursive_absolute("res://work/balance-night/" + revision + "/rogue")
		path = "res://work/balance-night/" + revision + "/rogue/%03d.json" % round_id
	if FileAccess.file_exists(path):
		printerr("Refusing to overwrite completed round: ", path)
		quit(1)
		return
	var expedition = Run.new(requested_line if requested_line > 0 else [3, 2, 1, 3, 2][(round_id - 1) % 5], requested_seed if requested_seed > 0 else 83000 + round_id * 137, ascension)
	if not checkpoint_path.is_empty():
		var config := ConfigFile.new()
		if config.load(checkpoint_path) != OK or not expedition.restore(config.get_value("rogue", "checkpoint")):
			printerr("Invalid earned-build checkpoint fixture: ", checkpoint_path)
			quit(1)
			return
	var starting_stage: int = expedition.stage
	var retries := 0
	var outcome := "defeat"
	while true:
		var game = load("res://main.tscn").instantiate()
		game.mode = "rogue"
		game.rogue = expedition
		game.simulation_mode = true
		root.add_child(game)
		game.set_physics_process(false)
		game.start_match()
		var initial_score: Array = game.score.duplicate()
		if not elite_trial.is_empty():
			assert(elite_trial.size() == 3)
			for actor in game.players:
				if actor.team == 1:
					var elite := maxi(0, expedition.stage - 10)
					actor.extra_bonuses = {"speed": elite * elite_trial[0], "kick": elite * elite_trial[1], "haste": elite * elite_trial[2]}
		game.player.human = true
		var ticks := 0
		while not game.finished and game.match_elapsed() < 600:
			if ticks % 12 == 0 and game.is_playing():
				control(game, round_id - 1 + retries)
			game._physics_process(1.0 / 60.0)
			ticks += 1
		var row := {"stage": expedition.stage, "decision_variant": round_id - 1 + retries, "attempt": rows.size() + 1, "allies": expedition.members.size() + 2,
			"enemies": expedition.opponent_count(), "initial_score": initial_score, "score": game.score.duplicate(), "won": game.result_won, "finished": game.finished,
			"seconds": game.match_elapsed(), "golden": game.overtime_count > 0, "player": game.player.stats.duplicate(),
			"goals": game.goal_events.duplicate(true), "build": expedition.snapshot(), "choices": [], "checkpoint_return": false}
		row["players"] = []
		for actor in game.players:
			row.players.append({"team": actor.team, "hero": actor.archetype, "human": actor.human, "stats": actor.stats.duplicate(), "bonuses": actor.extra_bonuses.duplicate()})
		rows.append(row)
		print("ROUND %d STAGE %02d %dv%d %s %s %.1fs" % [round_id, expedition.stage, row.allies, row.enemies,
			"WIN" if row.won else ("LOSS" if row.finished else "TIMEOUT"), str(row.score), row.seconds])
		var won: bool = game.result_won
		var finished: bool = game.finished
		game.free()
		if not finished:
			outcome = "timeout"
			break
		if won:
			if expedition.stage == Run.STAGES:
				outcome = "victory"
				break
			expedition.reward()
			row.choices.append(choose_reward(expedition, round_id - 1 + retries))
			if expedition.checkpoint_choice:
				row.choices.append(choose_reward(expedition, round_id - 1 + retries))
		elif not expedition.checkpoint.is_empty() and retries < 3:
			retries += 1
			row.checkpoint_return = true
			assert(expedition.restore(expedition.checkpoint.duplicate(true)))
		else:
			break
		await process_frame
	var result := {"round": round_id, "seed": expedition.seed_value, "line": expedition.start_line, "ascension": expedition.ascension, "curses": expedition.curses, "outcome": outcome, "starting_stage": starting_stage, "checkpoint_source": checkpoint_path, "elite_trial": elite_trial,
		"retries": retries, "matches": rows, "configuration": {"talents": Run.TALENTS, "quality_scale": Run.QUALITY_SCALE,
		"crowns": Run.CROWNS, "e_cooldowns": Run.E_COOLDOWNS, "enemy_roster": Run.OPPONENTS, "elite_per_stage_after_10": Run.ELITE_STEP, "ascension_growth_start": Run.ASCENSION_GROWTH_START, "ascension_growth": Run.ASCENSION_GROWTH, "quality_weights": Run.quality_weights(expedition.ascension), "final_trial": Run.FINAL_TRIAL, "final_trial_score": [0, 1], "both_ai": "hard", "initial_members": {"back": [0, 1], "mid": [0, 5], "front": [0, 1]}}}
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(result, "\t"))
	file.close()
	print("ROGUE ROUND COMPLETE: %d %s, %d matches, %d checkpoint returns" % [round_id, outcome, rows.size(), retries])
	quit()
