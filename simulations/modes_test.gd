extends SceneTree
const Shell = preload("res://scripts/game_shell.gd")
const Modes = preload("res://scripts/game_modes.gd")
var checks := 0
var failures := 0
var shell: Node


func _initialize() -> void:
	call_deferred("run")


func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
	print(("PASS: " if ok else "FAIL: ") + message)


func run() -> void:
	var path := "res://work/modes-test-progress.cfg"
	ConfigFile.new().save(path)
	shell = Shell.new()
	shell.simulation_mode = true
	shell.progress_path = path
	root.add_child(shell)
	check(shell.page == "home" and shell.completed == 0 and shell.game == null, "boot opens home, not a match")
	check(not shell.open_mode("conquest", 1) and not shell.open_mode("conquest", -1), "locked and invalid challenges cannot launch")
	check(Modes.CHALLENGES.size() == 15, "conquest contains all five old and ten new challenges")
	for level in range(Modes.CHALLENGES.size()):
		check(shell.open_mode("conquest", level), "unlocked challenge %d launches" % level)
		var game = shell.game
		game.set_physics_process(false)
		var rules: Dictionary = Modes.CHALLENGES[level]
		check(not game.choose_minutes(15) and not game.choose_difficulty(0), "challenge settings cannot be overridden")
		if rules.role == 4:
			game.choose_role(0)
			check(game.selected_role == 4 and game.player.goalkeeper, "keeper challenge locks the human role")
		game.start_match()
		check(game.regulation_duration == rules.seconds and game.difficulty == rules.difficulty and game.score == rules.score, "challenge applies duration difficulty and initial score")
		check(game.players.filter(func(p): return p.team == 0).size() == rules.team_size and game.players.filter(func(p): return p.team == 1).size() == 11, "challenge uses actual requested player counts")
		check(game.players.filter(func(p): return p.goalkeeper).size() == 2, "reduced roster preserves both keepers")
		if rules.team_size < 11:
			for formation in range(5):
				game.choose_formation(formation)
				check(game.players.size() == rules.team_size + 11 and is_instance_valid(game.player), "reduced roster supports formation %d" % formation)
			for role in range(6):
				game.choose_role(role)
				game.player.human = true
				game.assign_formation(0)
				check(game.players.size() == rules.team_size + 11 and game.player.archetype == role, "reduced roster can restart as hero %d without losing playable shirts" % role)
		game.skip_shop()
		check(game.carrier.team == rules.kickoff, "challenge uses its specified kickoff team")
		for frame in range(120):
			game._physics_process(1.0 / 60.0)
		check(game.match_elapsed() > 1.9 and not game.finished, "challenge runs actual simulation before objective is met")
		game.score = [0, 1]
		if rules.goal != "clean_sheet":
			game.time_left = 0.01
		game._physics_process(0.02)
		check(game.finished and not game.result_won and game.overtime_count == 0 and shell.completed == level, "missed objective fails without unlocking or overtime")
		shell.activate("retry")
		game = shell.game
		game.set_physics_process(false)
		check(game.score == rules.score and game.players.size() == rules.team_size + 11 and game.shop_open, "retry reconstructs exact scenario without accumulating roster changes")
		game.skip_shop()
		game.score = [rules.target, rules.target + 1] if rules.goal == "goals" else [rules.target, 0]
		if rules.goal != "goals":
			game.time_left = 0.01
		game._physics_process(0.02)
		check(game.finished and game.result_won and shell.page == "result" and shell.completed == level + 1, "valid objective clears and unlocks next challenge")
	var saved := Shell.new()
	saved.progress_path = path
	saved.load_progress()
	check(saved.completed == 15, "all fifteen clears persist after loading saved progress")
	saved.free()
	check(Modes.outcome(4, [2, 1], true) == 0 and Modes.outcome(4, [3, 1], true) == 1, "two-goal margin requires net lead, not merely two scored")
	check(Modes.outcome(5, [2, 2], true) == 1 and Modes.outcome(5, [2, 2], false) == -1, "equalizer permits a draw only at full time")
	check(Modes.outcome(5, [1, 1], true) == 1 and Modes.outcome(9, [1, 1], true) == 0, "draw allowance belongs only to the stated objectives")
	check(Modes.outcome(11, [3, 5], false) == 1, "three-goal challenge does not require winning the scoreline")
	for count in range(6):
		var legacy := ConfigFile.new()
		legacy.set_value("progress", "completed", count)
		legacy.set_value("progress", "tutorial", true)
		legacy.save("res://work/modes-legacy-progress.cfg")
		var migrated := Shell.new()
		migrated.progress_path = "res://work/modes-legacy-progress.cfg"
		migrated.load_progress()
		check(migrated.completed == count and migrated.tutorial_done and Modes.LEGACY_IDS.slice(0, count).all(func(id): return id in migrated.cleared), "legacy %d clears migrate by identity, with no invented new clears" % count)
		if count > 0:
			var last_index := 0
			for i in range(Modes.CHALLENGES.size()):
				if Modes.CHALLENGES[i].id in migrated.cleared:
					last_index = i
			check(migrated.unlocked_level() == last_index + 1, "legacy progress keeps previous access and opens the next challenge")
		migrated.save_progress()
		migrated.load_progress()
		check(migrated.completed == count and Modes.LEGACY_IDS.slice(0, count).all(func(id): return id in migrated.cleared), "migrated save round-trips without resetting or duplicating clears")
		migrated.free()
	shell._finished(true)
	check(shell.completed == 15, "replaying a completed challenge does not duplicate progress")
	shell.leave_session()
	shell.free_minutes = 15
	shell.free_difficulty = 2
	shell.free_ally_difficulty = 0
	shell.open_mode("free")
	var game = shell.game
	game.set_physics_process(false)
	check(game.ai_difficulty(0) == 0 and game.ai_difficulty(1) == 2, "shell restores independent teammate and opponent choices")
	game.choose_ally_difficulty(2)
	game.start_match()
	check(game.time_left == 900 and game.players.size() == 22 and game.difficulty == 2 and game.player.gold == 500, "free mode restores full roster with selected normal economy")
	game.skip_shop()
	game.time_left = 0.01
	game._physics_process(0.02)
	check(not game.finished and game.overtime_count == 1 and game.time_left == 120, "free mode retains full overtime")
	shell.open_mode("training", 0, 5, true)
	game = shell.game
	game.set_physics_process(false)
	check(game.players.size() == 2 and game.player.archetype == 5 and game.player.gold == 100000, "lab creates selected hero and stationary control target")
	game._physics_process(1.0)
	check(not game.finished and game.time_left == 900 and game.practice.elapsed == 1.0, "practice advances without consuming match clock")
	game.use_ability(game.player, Vector3.ZERO, game.players[1].position)
	game._apply_slow_fields()
	check(game.players[1].slow_multiplier < 1.0, "training dummy receives actual W effects")
	shell.activate("refill")
	check(game.player.ability_cooldown == 0 and game.player.e_charges[8] == 99, "lab refreshes cooldown and E stock")
	shell.activate("shop")
	game.buy_item(game.player, 14)
	game._physics_process(60.0)
	check(game.shop_open and 14 in game.player.inventory and game.practice.elapsed == 1.0, "training shop stays open without consuming practice time")
	game.skip_shop()
	shell.activate("reset")
	check(game.carrier == game.player and game.fields.is_empty() and 14 in game.player.inventory, "reset restores ball and positions while retaining chosen equipment")
	shell.open_mode("training", 0, 4, true)
	game = shell.game
	game.set_physics_process(false)
	shell.activate("shot")
	check(game.player.goalkeeper and game.carrier == null and game.ball.velocity.x < 0 and game.last_touch.team == 1, "keeper lab serves a real hostile incoming ball")
	shell.open_mode("tutorial")
	game = shell.game
	game.set_physics_process(false)
	check(game.selected_role == 0 and game.players.size() == 1 and game.practice.step == 0, "tutorial starts with controlled runner and no competing NPCs")
	game.practice.update(1.0)
	check(game.practice.step == 0, "tutorial never auto-completes without action")
	game.player.target = game.practice.waypoint
	for frame in range(120):
		game._physics_process(1.0 / 60.0)
	check(game.practice.step == 1 and game.carrier == game.player, "walking to marker advances movement lesson")
	game.player.target = game.practice.waypoint
	for frame in range(120):
		game._physics_process(1.0 / 60.0)
	check(game.practice.step == 2, "dribbling to marker advances ball lesson")
	game.player.facing = Vector3.RIGHT
	game.player_kick()
	for frame in range(180):
		game._physics_process(1.0 / 60.0)
	check(game.practice.step == 3 and game.score[0] == 1 and not game.shop_open, "actual Q shot scores and advances shooting lesson without goal shop")
	game.use_ability(game.player)
	game._physics_process(1.0 / 60.0)
	check(game.practice.step == 3 and not game.shop_open, "W does not interrupt the sprint after one frame")
	for frame in range(130):
		game._physics_process(1.0 / 60.0)
	check(game.practice.step == 3, "casting and waiting without reaching the target does not finish W practice")
	game.player.target = game.practice.waypoint
	for frame in range(180):
		game._physics_process(1.0 / 60.0)
	check(game.practice.step == 4 and game.shop_open, "W practice advances after time to observe and movement to the target")
	game.buy_e(game.player, 0)
	game.skip_shop()
	game.use_e(game.player)
	game._physics_process(1.0 / 60.0)
	check(not game.finished and game.player.e_boost_time > 0, "E remains playable after casting")
	game.player.target = game.practice.waypoint
	for frame in range(60):
		game._physics_process(1.0 / 60.0)
	check(not game.finished, "E practice allows time to feel the speed boost")
	for frame in range(120):
		game._physics_process(1.0 / 60.0)
	check(game.finished and shell.tutorial_done and shell.page == "result", "buying and casting E completes the interactive tutorial")
	shell.open_mode("free")
	shell.game.set_physics_process(false)
	shell.game.start_match()
	check(shell.game.player.gold == 500 and shell.game.player.e_charges.is_empty() and shell.game.players.size() == 22, "training currency charges and roster never leak into normal play")
	check(shell.game.ai_difficulty(0) == 2 and shell.game.ai_difficulty(1) == 2, "free teammate selection survives visiting practice and tutorial")
	shell.leave_session()
	check(shell.game == null and shell.page == "home", "return home releases the running match")
	print("RESULT: %d checks, %d failures" % [checks, failures])
	shell.free()
	quit(1 if failures else 0)
