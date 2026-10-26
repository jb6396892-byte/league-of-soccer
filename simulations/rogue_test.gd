extends SceneTree
const Shell = preload("res://scripts/game_shell.gd")
const Run = preload("res://scripts/rogue_run.gd")
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


func launch(line: int, stage: int = 1) -> Node:
	shell.rogue = Run.new(line, 99101)
	shell.rogue.stage = stage
	shell.launch_rogue_stage()
	var game = shell.game
	game.set_physics_process(false)
	game._physics_process(game.goal_pause + 0.01)
	return game


func goal(game: Node, team: int) -> void:
	game.last_touch = game.players.filter(func(p): return p.team == team)[0]
	game.carrier = null
	game.ball.position = Vector3((game.Stadium.HALF_LENGTH + 1) * (1 if team == 0 else -1), 0.5, 0)
	game._check_boundaries()


func run() -> void:
	ConfigFile.new().save("res://work/rogue-test-progress.cfg")
	shell = Shell.new()
	shell.simulation_mode = true
	shell.progress_path = "res://work/rogue-test-progress.cfg"
	root.add_child(shell)
	for line in [1, 2, 3]:
		var game = launch(line)
		check(game.players.filter(func(p): return p.team == 0).size() == 4, "player + two field teammates + keeper")
		check(game.player.tactical_line == line and not game.player.goalkeeper, "chosen starting line is applied")
		check(is_equal_approx(game.player.move_speed(), 7.8) and game.player.hit_scale() == 1.0, "blank hero has no inherited passive")
		check(not game.use_ability(game.player) and not game.use_e(game.player), "blank hero has no W or E")
		check(shell.rogue.talent_kind_count() == 0, "blank build has no talents")
		var current = game.player
		game.choose_role(4)
		check(game.player == current and not game.player.goalkeeper, "role switching cannot bypass blank start")
		game.time_left = 70
		game.start_match()
		check(game.time_left == 70, "cannot restart current rogue stage")
		check(not game.buy_item(game.player, 0) and not game.buy_e(game.player, 0), "shop growth unavailable in rogue")
		for tick in range(180):
			game._physics_process(1.0 / 60.0)
		check(game.time_left < 68 and not game.finished, "small squads run actual AI and physics")
	var game = launch(3)
	check(game.carrier.team == 0 and game.time_left == 90, "first stage opens for blue after countdown without consuming match time")
	for scorer in [0, 0, 1, 0]:
		goal(game, scorer)
		var saved_time: float = game.time_left
		game._physics_process(game.goal_pause + 0.01)
		check(game.carrier.team == 1 - scorer and game.time_left == saved_time, "conceding side keeps kickoff after the entire goal countdown")
	check(game.score == [3, 1] and not game.finished, "two-goal lead continues")
	goal(game, 0)
	check(game.score == [4, 1] and game.finished and game.result_won, "4:1 immediately wins by three-goal lead")
	game = launch(3)
	for ignored in range(3):
		goal(game, 1)
		game._physics_process(game.goal_pause + 0.01)
	check(game.score == [0, 3] and not game.finished, "0:3 still allows a comeback before full time")
	for stage in [1, 20]:
		game = launch(2, stage)
		game.time_left = 45
		for ignored in range(2):
			goal(game, 0)
			game._physics_process(game.goal_pause + 0.01)
			check(not game.finished, "one or two unanswered goals do not end regulation early")
		goal(game, 0)
		check(game.finished and game.result_won and game.score == [3, 0] and game.time_left == 45, "third unanswered goal immediately wins without waiting for full time")
		if stage == 1:
			check(shell.page == "rogue_reward" and shell.rogue.offers.size() == 3 and shell.rogue.stage == 1, "early victory grants one normal three-choice reward")
			shell.activate("talent:0")
			game = shell.game
			game.set_physics_process(false)
			game._physics_process(game.goal_pause + 0.01)
			check(shell.rogue.stage == 2 and game.score == [0, 0] and game.time_left == 90 and game.carrier.team == 1, "choosing early-win reward starts fresh stage two with opposing kickoff")
		else:
			check(shell.page == "rogue_result" and shell.rogue.ended and not shell.rogue.awaiting_reward and shell.rogue.stage == 20, "3:0 in final stage completes expedition without stage twenty-one")
	game = launch(3)
	goal(game, 1)
	check(not game.finished and game.score == [0, 1] and not game.shop_open, "falling behind before full time is not defeat")
	game.goal_pause = 0
	game.time_left = 0.01
	game._physics_process(0.02)
	check(shell.page == "rogue_result" and shell.rogue.ended and not game.result_won, "losing at 90 seconds ends run")
	check(not shell.rogue.choose(0), "defeat offers no growth or retry continuation")
	for winner in [0, 1]:
		game = launch(2, winner + 1)
		game.score = [2, 2]
		game.time_left = 0.01
		game._physics_process(0.02)
		check(not game.finished and game.overtime_count == 1 and not game.shop_open, "tie starts golden goal without shop")
		game._physics_process(game.goal_pause + 0.01)
		check(game.carrier.team == shell.rogue.stage % 2, "golden-goal kickoff changes sides and survives countdown")
		for tick in range(120):
			game._physics_process(1.0 / 60.0)
		check(game.rogue_extra_time > 1.9 and game.overtime_count == 1, "golden goal clock advances without repeating overtime")
		goal(game, winner)
		check(game.finished and game.result_won == (winner == 0), "first actual goal decides overtime")
		check(shell.page == ("rogue_reward" if winner == 0 else "rogue_result"), "golden goal reaches correct page")
	game = launch(1)
	shell.rogue.w_skill = 5
	check(shell.rogue.talent_kind_count() == 1, "learning W alone counts as one talent")
	shell.rogue.e_skill = 0
	check(shell.rogue.talent_kind_count() == 2, "learning E adds a talent")
	shell.rogue.talents = {"pace": 2, "runner": 1, "haste": 2, "keeper": 1}
	check(shell.rogue.talent_kind_count() == 6, "talent types include skills and count repeated stat upgrades only once")
	shell.launch_rogue_stage()
	game = shell.game
	game.set_physics_process(false)
	game.goal_pause = 0
	game.player.position.x = 20
	check(is_equal_approx(game.player.move_speed(), 7.8 * 1.21), "growth applies without Warden away-half passive")
	check(game.player.tactical_line == 1 and game.player.archetype == 5, "learning W does not change selected line")
	check(game.use_ability(game.player, Vector3.RIGHT, Vector3(25, 0, 0)), "learned W creates actual domain")
	check(game.fields.size() == 1 and is_equal_approx(game.player.ability_cooldown, 60.0 / 1.4), "talent haste affects W")
	check(game.use_e(game.player) and game.player.e_charges.is_empty(), "learned E works with no charges")
	check(not game.use_e(game.player) and is_equal_approx(game.player.e_cooldown, 16.0 / 1.4), "E still obeys cooldown with haste")
	game.player.e_cooldown = 0
	check(game.use_e(game.player), "permanent E can be cast again")
	check(is_equal_approx(game.player.e_boost_multiplier, 1.10) and game.player.e_boost_time == 1.8, "unlimited E has reduced speed and duration")
	var keeper = game.players.filter(func(p): return p.team == 0 and p.goalkeeper)[0]
	check(is_equal_approx(keeper.save_window(), 0.88) and is_equal_approx(keeper.equipment_bonus("speed"), 0.12), "team and goalkeeper talents reach correct actors")
	for quality in range(3):
		shell.rogue.e_quality = quality
		for skill in range(3):
			game.player.e_selected = skill
			game.player.e_cooldown = 0
			game.player.e_boost_time = 0
			game.player.e_immunity_time = 0
			game.carrier = game.player
			game.possession_lock = 0
			check(game.use_e(game.player), "each quality of permanent E remains usable")
			match skill:
				0: check(is_equal_approx(game.player.e_boost_multiplier, 1.10 + quality * 0.02) and game.player.e_boost_time == 1.8, "higher-quality haste is stronger but stays weaker than purchased E")
				1: check(is_equal_approx(game.player.e_immunity_time, 0.7 + quality * 0.2), "cleanse immunity grows with quality and remains shortened")
				2: check(is_equal_approx(game.possession_lock, 0.6 + quality * 0.15), "protection grows with quality and remains shortened")
	for quality in range(3):
		game = launch(2)
		shell.rogue.awaiting_reward = true
		shell.rogue.offers.assign([{"type": "stat", "value": "runner", "quality": quality}])
		shell.rogue.choose(0)
		shell.rogue.apply_growth(game)
		check(is_equal_approx(game.player.move_speed(), 7.8 * (1.0 + 0.09 * Run.QUALITY_SCALE[quality])), "stat rarity changes actual player movement")
	# Exercise the complete twenty-stage transition through actual full-time outcome handling.
	game = launch(3)
	var previous_enemy := 0
	var previous_difficulty := 0
	for stage in range(1, 21):
		game = shell.game
		game.set_physics_process(false)
		game._physics_process(game.goal_pause + 0.01)
		check(game.carrier.team == (stage - 1) % 2, "starting kickoff alternates throughout all twenty stages")
		check(shell.rogue.stage == stage and game.regulation_duration == 90, "each stage has a fresh 90-second clock")
		var enemies: Array = game.players.filter(func(p): return p.team == 1)
		check(enemies.size() >= previous_enemy and game.difficulty >= previous_difficulty, "enemy roster and difficulty never shrink")
		check(game.players.filter(func(p): return p.goalkeeper).size() == 2, "all stages retain one keeper per side")
		check(game.players.all(func(p): return game.ai_profile(p) == game.Settings.PROFILES[2]), "both teams use HARD decisions on every stage")
		previous_enemy = enemies.size()
		previous_difficulty = game.difficulty
		if stage == 20:
			check(enemies.size() == 11 and game.difficulty == 2 and is_equal_approx(enemies[0].equipment_bonus("speed"), 0.12), "final opponent is eleven-player HARD with capped expedition-only elite growth")
		game.score = [1, 0]
		game.time_left = 0.01
		game._physics_process(0.02)
		if stage < 20:
			check(shell.page == "rogue_reward" and shell.rogue.offers.size() == 3, "win gives exactly three choices")
			var offers: Array = shell.rogue.offers
			check(offers[0].name != offers[1].name and offers[0].name != offers[2].name and offers[1].name != offers[2].name, "reward choices are distinct")
			var choice := 0
			for i in range(offers.size()):
				if offers[i].type == "recruit":
					choice = i
				if offers[i].type == "stat":
					check(shell.rogue.talents.get(offers[i].value, 0) < Run.TALENTS[offers[i].value].cap, "capped talent is not offered")
			shell.activate("talent:%d" % choice)
			if stage in Run.CHECKPOINTS:
				check(shell.rogue.stage == stage and shell.rogue.checkpoint_choice and shell.rogue.offers.size() == 3, "milestone grants extra top-tier choice before advancing")
				check(shell.rogue.offers.all(func(o): return o.quality == 3 and o.value not in shell.rogue.crowns), "top-tier choices are exclusive and never repeat owned crowns")
				shell.activate("talent:0")
				var saved: Dictionary = shell.rogue.checkpoint.duplicate(true)
				check(shell.rogue.stage == stage + 1 and saved.crowns.size() == stage / 5, "checkpoint captures next stage and selected crown exactly once")
				var reader = Shell.new()
				reader.simulation_mode = true
				reader.progress_path = shell.progress_path
				root.add_child(reader)
				check(reader.rogue_checkpoint == saved, "fresh shell reloads checkpoint from disk including exact RNG state")
				reader.free()
				var expected = Run.new()
				expected.restore(saved)
				expected.reward()
				game = shell.game
				game.set_physics_process(false)
				game.goal_pause = 0
				game.score = [0, 1]
				game.time_left = 0.01
				game._physics_process(0.02)
				shell.rogue.talents.runner = 4
				shell.activate("rogue_resume")
				check(shell.rogue.snapshot() == saved and shell.game.score == [0, 0] and shell.game.time_left == 90, "defeat rollback discards later growth and restores fresh match")
				var probe = Run.new()
				probe.restore(shell.rogue.checkpoint)
				probe.reward()
				check(probe.offers == expected.offers, "rollback preserves reward RNG and cannot reroll talents")
			check(not shell.rogue.choose(choice), "finished choice cannot be applied twice")
		else:
			check(shell.page == "rogue_result" and shell.rogue.ended and not shell.rogue.awaiting_reward, "stage twenty ends in victory without a twenty-first stage")
	check(shell.rogue.members.size() == 9, "recruitment caps squad at eleven")
	shell.activate("rogue")
	check(shell.rogue == null and shell.game == null and shell.page == "rogue_setup", "new expedition clears run state")
	game = launch(2)
	check(shell.rogue.talents.is_empty() and game.players.size() == 7 and not game.player.w_unlocked, "new run starts blank with four allies against three enemies")
	shell.leave_session()
	shell.open_mode("free")
	shell.game.start_match()
	check(shell.game.players.size() == 22 and shell.game.player.w_unlocked and not shell.game.player.rogue_player and shell.game.player.extra_bonuses.is_empty() and shell.game.player.gold == 500, "rogue growth does not leak to other modes")
	game = shell.game
	game.set_physics_process(false)
	game.skip_shop()
	for ignored in range(3):
		goal(game, 0)
		game._physics_process(game.goal_pause + 0.01)
		check(not game.finished and game.carrier.team == 1, "free match retains conceding-side kickoff and has no 3:0 early victory")
	var distribution := [0, 0, 0]
	for roll in range(100):
		distribution[Run.quality_for_roll(roll)] += 1
	check(distribution == [60, 30, 10], "rarity buckets have exact 60/30/10 weights")
	var sampled := [0, 0, 0]
	var lottery = Run.new(2, 7621)
	for i in range(3000):
		lottery.awaiting_reward = false
		lottery.reward()
		for offer in lottery.offers:
			sampled[offer.quality] += 1
	check(absf(sampled[0] / 9000.0 - 0.6) < 0.02 and absf(sampled[1] / 9000.0 - 0.3) < 0.02 and absf(sampled[2] / 9000.0 - 0.1) < 0.02, "actual generated reward qualities follow configured distribution")
	print("QUALITY SAMPLE: ", sampled)
	check(not lottery.restore({"stage": 6}), "incomplete save is rejected without partially loading")
	shell.free()
	print("ROGUE RESULT: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
