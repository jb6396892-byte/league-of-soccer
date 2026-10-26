extends SceneTree
const Controller = preload("res://simulations/balance_controller.gd")
const Net = preload("res://scripts/net_session.gd")
var suite := "free"
var revision := "baseline"
var first := 0
var count := 36
var difficulty := 1
var minutes := 5

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		var value := arg.get_slice("=", 1)
		match arg.get_slice("=", 0):
			"--suite": suite = value
			"--revision": revision = value
			"--start": first = int(value)
			"--count": count = int(value)
			"--difficulty": difficulty = int(value)
			"--minutes": minutes = int(value)
	call_deferred("run")

func write_json(path: String, data: Variant) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(data, "\t"))
	file.close()

func run() -> void:
	var output := "res://work/balance-night/" + revision + "/" + suite + "/"
	DirAccess.make_dir_recursive_absolute(output)
	var wall_start := Time.get_ticks_msec()
	for sample in range(first, first + count):
		var path := output + "%03d.json" % sample
		if FileAccess.file_exists(path):
			printerr("Refusing to overwrite: ", path)
			quit(1)
			return
		var role: int = sample % 6 if suite == "free" else (sample / 2) % 6
		var leg: int = sample / 18 if suite == "free" else sample % 2
		var seed_value: int = 940000 + leg * 101 if suite == "free" else 950000 + (sample / 2) * 31
		var game = load("res://main.tscn").instantiate()
		game.simulation_mode = true
		game.match_minutes = minutes
		game.difficulty = (sample / 6) % 3 if suite == "free" else difficulty
		if suite != "free":
			game.net = Net.new()
			game.net.hosting = true
			game.add_child(game.net)
		root.add_child(game)
		game.set_physics_process(false)
		game.choose_role(role)
		for actor in game.players:
			actor.human = false
		var controlled: Array = []
		if suite == "free":
			controlled.append(game.player)
		elif suite == "pvp":
			for team in range(2):
				var actor = game.players[team * 11 + (0 if role == 4 else 9)]
				actor.set_archetype(role)
				controlled.append(actor)
		else:
			var team := leg
			var actor = game.players[team * 11 + (0 if role == 4 else 9)]
			actor.set_archetype(role)
			controlled.append(actor)
			var other_role: int = (role + 3) % 6
			var other = game.players[team * 11 + (0 if other_role == 4 else 8)]
			other.set_archetype(other_role)
			controlled.append(other)
		game.player = controlled[0]
		for actor in controlled:
			actor.human = true
		game.rng.seed = seed_value
		game.start_match()
		game.team_formations = [1, 1]
		game.rng.seed = seed_value
		for team in range(2):
			game.assign_formation(team, true)
		if suite == "pvp":
			for slot in range(11):
				game.players[slot + 11].set_archetype(game.players[slot].archetype)
			game.assign_formation(1)
		for actor in game.players:
			actor.build_variant = (actor.shirt_number + leg) % 3
		game.reset_kickoff(leg % 2)
		game.open_shop(leg % 2, "平衡测试赛前准备")
		var config := {"items": game.Gear.ITEMS, "builds": game.Gear.NPC_BUILDS, "skills": game.ESkills.SKILLS,
			"profiles": game.Settings.PROFILES, "tactics": game.NPCTactics.TUNE, "speed": game.Roles.SPEED,
			"duration": game.Roles.DURATION, "cooldown": game.Roles.COOLDOWN, "start_gold": game.Gear.START_GOLD,
			"stipend": game.Gear.STIPEND_GOLD, "team_speed_gain": game.Gear.TEAM_SPEED_GAIN, "team_speed_loss": game.Gear.TEAM_SPEED_LOSS, "team_upgrade_cap": game.Gear.TEAM_UPGRADE_CAP}
		if sample == first:
			write_json(output + "config-%03d.json" % first, config)
		var ticks := 0
		var max_speed := 0.0
		while not game.finished and game.match_elapsed() < minutes * 60 + 600:
			if game.shop_open:
				# Shopping follows legal NPC purchase routes; restore humans BEFORE kickoff reset.
				for actor in controlled:
					actor.human = false
				game._npc_shop()
				game.npc_shopped = true
				for actor in controlled:
					actor.human = true
				game.skip_shop()
			if ticks % 12 == 0 and game.is_playing():
				for actor in controlled:
					Controller.control(game, actor, leg)
			game._physics_process(1.0 / 60.0)
			if ticks % 60 == 0:
				for actor in game.players:
					max_speed = maxf(max_speed, actor.move_speed())
			ticks += 1
		var actors: Array = []
		for actor in game.players:
			actors.append({"team": actor.team, "shirt": actor.shirt_number, "hero": actor.archetype,
				"human": actor.human, "stats": actor.stats.duplicate(), "inventory": actor.inventory.duplicate(),
				"gold": actor.gold, "team_purchases": actor.team_purchases.duplicate(), "e_charges": actor.e_charges.duplicate()})
		write_json(path, {"sample": sample, "suite": suite, "seed": seed_value, "hero": role, "leg": leg,
			"difficulty": game.difficulty, "minutes": minutes, "controlled_team": controlled[0].team,
			"score": game.score, "seconds": game.match_elapsed(), "finished": game.finished, "overtime": game.overtime_count,
			"players": actors, "purchases": game.purchase_events, "e_purchases": game.e_purchase_events,
			"e_casts": game.e_cast_events, "goals": game.goal_events, "passes": game.tactics.pass_events,
			"timeouts": game.timeout_events,
			"keepers": game.tactics.keeper_events, "q_actions": game.tactics.q_events, "phases": game.tactics.phase_seconds,
			"loose_seconds": game.loose_ball_seconds, "max_speed": max_speed, "team_upgrades": game.team_upgrades})
		print("%s %03d hero%d diff%d team%d %s %s %.0fs speed%.1f" % [suite, sample, role, game.difficulty, controlled[0].team, str(game.score), "DONE" if game.finished else "CAPPED", game.match_elapsed(), max_speed])
		game.free()
		await process_frame
	print("CAMPAIGN COMPLETE %s %s wall %.1fs" % [revision, suite, (Time.get_ticks_msec() - wall_start) / 1000.0])
	quit()
