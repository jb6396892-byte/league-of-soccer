extends SceneTree
const Run = preload("res://scripts/rogue_run.gd")
const Shell = preload("res://scripts/game_shell.gd")
var checks := 0
var failures := 0
var shell: Node


func _initialize() -> void:
	call_deferred("run")


func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: " + message)


func launch(level: int, stage: int = 1) -> Node:
	shell.rogue = Run.new(2, 99713, level)
	shell.rogue.stage = stage
	shell.launch_rogue_stage()
	shell.game.set_physics_process(false)
	return shell.game


func stat_reward(run_state: RefCounted, id: String, quality: int) -> void:
	run_state.awaiting_reward = true
	run_state.offers.assign([{"type": "stat", "value": id, "quality": quality}])
	check(run_state.choose(0), "stat reward is applied")


func run() -> void:
	ConfigFile.new().save("res://work/ascension-test-progress.cfg")
	shell = Shell.new()
	shell.simulation_mode = true
	shell.progress_path = "res://work/ascension-test-progress.cfg"
	root.add_child(shell)
	shell.clear_rogue_checkpoint()
	check(shell.rogue_unlocked == 0 and shell.rogue_ascension == 0, "new player defaults to ascension zero only")
	shell.activate("rogue")
	shell.activate("ascension:5")
	shell.activate("rogue_start:2")
	check(shell.game == null and shell.page == "rogue_setup", "locked preview cannot start an expedition")
	for stage in [1, 5, 10, 15, 19, 20]:
		var previous := {}
		var ally_bonuses: Array = []
		for level in range(6):
			var game = launch(level, stage)
			var enemy: Dictionary = shell.rogue.enemy_bonuses()
			check(game.difficulty == 2 and game.players.all(func(p): return game.ai_difficulty(p.team) == 2), "both sides retain HARD decisions")
			var initial_score := [0, 1] if level == 5 and stage == 20 else [0, 0]
			check(game.time_left == 90 and game.score == initial_score and shell.rogue.opponent_count() <= 11, "only final trial starts a goal behind; regulation and roster limits remain")
			check(game.players.filter(func(p): return p.team == 1).all(func(p): return p.extra_bonuses == enemy), "enemy modifiers actually reach every opponent")
			var allies: Array = game.players.filter(func(p): return p.team == 0).map(func(p): return p.extra_bonuses.duplicate())
			if level == 0:
				ally_bonuses = allies
			else:
				check(allies == ally_bonuses, "ascension penalty never buffs allies")
				check(enemy.keys().all(func(key): return enemy[key] >= previous.get(key, 0.0)), "cumulative enemy attributes never decrease")
			if stage == 1:
				check(is_equal_approx(enemy.speed, 0.0 if level == 0 else 0.05), "initial speed modifier is exactly five percent")
			if level == 5:
				check((enemy == previous) == (stage != 20), "final-trial bonus starts only in the final match")
			previous = enemy
	for level in range(6):
		var distribution := [0, 0, 0]
		var never_upgrades := true
		for roll in range(100):
			var quality: int = Run.quality_for_roll(roll, level)
			distribution[quality] += 1
			never_upgrades = never_upgrades and quality <= Run.quality_for_roll(roll, 0)
		check(never_upgrades, "scarcity never upgrades the same quality roll")
		check(distribution == ([60, 30, 10] if level < 3 else [80, 17, 3]), "quality buckets match each ascension")
	var lottery = Run.new(2, 7621, 3)
	var sampled := [0, 0, 0]
	for i in range(3000):
		lottery.awaiting_reward = false
		lottery.reward()
		for offer in lottery.offers:
			sampled[offer.quality] += 1
	check(absf(sampled[0] / 9000.0 - 0.8) < 0.02 and absf(sampled[1] / 9000.0 - 0.17) < 0.02 and absf(sampled[2] / 9000.0 - 0.03) < 0.01, "actual scarce offers follow the distribution")
	print("SCARCE QUALITY SAMPLE: ", sampled)
	# Every representable old build retains its exact rank distribution.
	for count in range(1, 5):
		for strong in range(count + 1):
			for rare in range(count - strong + 1):
				var common: int = count - strong - rare
				var ranks: Array = Run.ranks_for_power(count, common + rare * 1.6 + strong * 2.3)
				check(ranks.count(0) == common and ranks.count(1) == rare and ranks.count(2) == strong, "old weighted ranks reconstruct without losing quality")
	# Strong -> rare at rest five; rare -> common at rest ten; no target at rest fifteen.
	var cursed = Run.new(2, 90210, 4)
	stat_reward(cursed, "runner", 2)
	cursed.w_skill = 5
	cursed.e_skill = 1
	cursed.w_quality = 2
	cursed.e_quality = 2
	for stage in Run.CHECKPOINTS:
		cursed.stage = stage
		var rng_before: int = cursed.rng.state
		var members_before: Array = cursed.members.duplicate()
		cursed.apply_rest_curse()
		var power_after: float = cursed.talent_power.runner
		check(is_equal_approx(power_after, 1.6 if stage == 5 else 1.0), "rest always replaces one eligible rank with the next lower rank")
		check(cursed.rng.state == rng_before, "curse does not change reward RNG")
		check(cursed.talents.runner == 1 and cursed.w_skill == 5 and cursed.w_quality == 2 and cursed.e_quality == 2 and cursed.members == members_before, "curse preserves type, stack count, skills and teammates")
		cursed.apply_rest_curse()
		check(cursed.talent_power.runner == power_after and cursed.curses.size() == stage / 5, "one curse at each rest, without repeat application")
		check(not cursed.curse_text().is_empty(), "rest explains its curse or missing target")
		cursed.crown_reward()
		check(cursed.offers.all(func(o): return o.quality == 3), "crown offers are protected from scarcity and curses")
		cursed.choose(0)
		var saved: Dictionary = cursed.checkpoint.duplicate(true)
		var restored = Run.new()
		check(restored.restore(saved) and restored.snapshot() == saved, "checkpoint roundtrip preserves ascension, cursed stats and RNG")
		shell.rogue = restored
		shell.save_rogue_checkpoint()
		var reader = Shell.new()
		reader.simulation_mode = true
		reader.progress_path = shell.progress_path
		root.add_child(reader)
		reader.rogue_ascension = 0
		reader.resume_rogue()
		reader.game.set_physics_process(false)
		check(reader.rogue.ascension == 4 and reader.rogue.snapshot() == saved, "disk resume uses saved difficulty, not current menu selection")
		check(is_equal_approx(reader.game.player.equipment_bonus("speed"), power_after * Run.TALENTS.runner.value + (0.10 if "captain" in restored.crowns else 0.0) + (0.16 if "ace" in restored.crowns else 0.0)), "downgrade changes actual player speed bonus")
		reader.free()
		var expected = Run.new()
		expected.restore(saved)
		expected.reward()
		restored.reward()
		check(expected.offers == restored.offers, "resuming a cursed save cannot reroll its next reward")
		var bad := saved.duplicate(true)
		bad.ascension = 6
		check(not Run.new().restore(bad), "out-of-range saved ascension is rejected")
		bad = saved.duplicate(true)
		bad.curses.clear()
		check(not Run.new().restore(bad), "missing curse history cannot restore a cursed checkpoint")
		bad = saved.duplicate(true)
		bad.power.runner = 1.3
		check(not Run.new().restore(bad), "impossible stored talent ranks are rejected")
	var legacy: Dictionary = cursed.checkpoint.duplicate(true)
	legacy.erase("ascension")
	legacy.erase("curses")
	var old = Run.new()
	check(old.restore(legacy) and old.ascension == 0 and old.talent_power == legacy.power, "old checkpoint migrates to ascension zero with identical growth")
	var final_game = launch(5, 20)
	final_game.goal_pause = 0
	final_game.score = [1, 1]
	final_game.time_left = 0.01
	final_game._physics_process(0.02)
	check(not final_game.finished and final_game.overtime_count == 1, "equalizing the final trial earns golden-goal overtime")
	final_game.last_touch = final_game.player
	final_game.carrier = null
	final_game.ball.position = Vector3(final_game.Stadium.HALF_LENGTH + 1, 0.5, 0)
	final_game._check_boundaries()
	check(final_game.finished and final_game.result_won and final_game.score == [2, 1], "final-trial golden goal wins normally")
	final_game = launch(5, 20)
	final_game.goal_pause = 0
	final_game.score = [3, 1]
	final_game.last_touch = final_game.player
	final_game.carrier = null
	final_game.ball.position = Vector3(final_game.Stadium.HALF_LENGTH + 1, 0.5, 0)
	final_game._check_boundaries()
	check(final_game.finished and final_game.result_won and final_game.score == [4, 1] and final_game.time_left == 90, "final trial still awards a three-goal lead immediately")
	# Only a final-stage win can unlock the next level, and progress survives restart.
	for level in range(6):
		var game = launch(level, 19)
		game.finish_session(true)
		check(shell.rogue_unlocked == level, "penultimate win never unlocks next difficulty")
		game = launch(level, 20)
		game.finish_session(false)
		check(shell.rogue_unlocked == level, "final defeat never unlocks next difficulty")
		game = launch(level, 20)
		game.finish_session(true)
		check(shell.rogue_cleared == level and shell.rogue_unlocked == mini(5, level + 1), "final victory unlocks exactly the next ascension")
		var reader = Shell.new()
		reader.simulation_mode = true
		reader.progress_path = shell.progress_path
		root.add_child(reader)
		check(reader.rogue_cleared == level and reader.rogue_unlocked == shell.rogue_unlocked, "unlocks survive a fresh shell")
		reader.free()
	shell.rogue_ascension = 5
	shell.start_rogue(3)
	check(shell.rogue.ascension == 5 and shell.rogue.stage == 1 and shell.rogue.talents.is_empty(), "unlocked advanced run starts blank at its selected level")
	shell.leave_session()
	shell.open_mode("free", 0, 0, true)
	check(shell.game.players.all(func(p): return p.extra_bonuses.is_empty()), "ascension growth stays out of free mode")
	shell.free()
	print("ASCENSION RESULT: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
