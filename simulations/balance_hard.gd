extends SceneTree
## Adaptive campaign: one mirrored pair per invocation, then adjust before the next pair.
const Roles = preload("res://scripts/archetypes.gd")
const Gear = preload("res://scripts/equipment.gd")
const ES = preload("res://scripts/purchasable_skills.gd")
const Formations = preload("res://scripts/formations.gd")
const OUTPUT := "res://work/balance-hard/"
var first := 1
var last := 2
var batch := 1


func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--batch="):
			batch = int(argument.get_slice("=", 1))
	assert(batch >= 1 and batch <= 10)
	first = batch * 2 - 1
	last = batch * 2
	call_deferred("run")


func save_json(path: String, data: Variant) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(data, "\t"))
	file.close()


func run() -> void:
	DirAccess.make_dir_recursive_absolute(OUTPUT)
	var game = load("res://main.tscn").instantiate()
	game.simulation_mode = true
	root.add_child(game)
	game.set_physics_process(false)
	game.difficulty = game.Settings.Difficulty.HARD
	var started := Time.get_ticks_msec()
	save_json(OUTPUT + "configuration-%02d.json" % batch, {"items": Gear.ITEMS, "skills": ES.SKILLS, "npc_builds": Gear.NPC_BUILDS,
		"difficulty": game.difficulty, "profiles": game.Settings.PROFILES, "npc_tactics": game.NPCTactics.TUNE, "batch": batch, "hero_names": Roles.NAMES, "hit_scale": Roles.HIT_SCALE,
		"sprint": Roles.SPRINT_MULTIPLIER, "slow": Roles.SLOW_MULTIPLIER, "throw_speed": Roles.THROW_SPEED, "stun": Roles.STUN_SECONDS,
		"economy": {"start": Gear.START_GOLD, "stipend": Gear.STIPEND_GOLD, "stipend_seconds": Gear.STIPEND_SECONDS, "goal": Gear.GOAL_GOLD, "team_goal": Gear.TEAM_GOAL_GOLD, "tackle": Gear.TACKLE_GOLD, "intercept": Gear.INTERCEPT_GOLD, "possession": Gear.POSSESSION_GOLD, "possession_seconds": Gear.POSSESSION_SECONDS, "stun": Gear.STUN_GOLD}, "speed": Roles.SPEED, "cooldown": Roles.COOLDOWN, "duration": Roles.DURATION,
		"supply_seconds": Gear.SUPPLY_SECONDS,
		"domain": {"radius": Roles.DOMAIN_RADIUS, "range": Roles.DOMAIN_RANGE, "slow": 0.3, "seconds": Roles.DURATION[5], "cooldown": Roles.COOLDOWN[5]},
		"physics_hz": 60, "regulation_seconds": 300, "overtime_seconds": 120, "games": 20,
		"setup": "10 pairs; red HARD / blue NORMAL; identical pair seed; mirrored rosters/build routes/kickoff; two of each field hero per side, one keeper; both AI teams adjust formations by score at shops"})
	for number in range(first, last + 1):
		var output := OUTPUT + "match-%02d.json" % number
		if FileAccess.file_exists(output):
			printerr("Refusing to overwrite completed match: " + output)
			game.free()
			quit(1)
			return
		var pair := (number - 1) / 2
		var leg := (number - 1) % 2
		var roster: Array = []
		var builds: Array = []
		var roster_rng := RandomNumberGenerator.new()
		roster_rng.seed = 21100 + pair
		for team in range(2):
			roster.append(Roles.Kind.KEEPER)
			builds.append((pair + team) % 3)
			var field_roles: Array = [0, 0, 1, 1, 2, 2, 3, 3, 5, 5]
			for slot in range(10):
				roster.append(field_roles.pop_at(roster_rng.randi_range(0, field_roles.size() - 1)))
				builds.append((pair + team + slot) % 3)
		var seed_value := 81100 + pair
		game.rng.seed = seed_value
		for i in range(22):
			game.players[i].archetype = roster[i if leg == 0 else (i + 11) % 22]
		game.start_match()
		game.team_formations = [pair % 5, pair % 5]
		for i in range(22):
			game.players[i].build_variant = builds[i if leg == 0 else (i + 11) % 22]
		game.reset_kickoff(leg)
		game.open_shop(leg, "模拟赛前购买")
		var phase: Array = []
		var phase_start := 0.0
		var equipment: Array = []
		for item in Gear.ITEMS:
			equipment.append({"name": item.name, "equipped_seconds": 0.0, "goals": 0, "tackles": 0, "possession_seconds": 0.0})
		var starting: Array = []
		for actor in game.players:
			starting.append({"team": actor.team, "shirt_number": actor.shirt_number, "role": actor.archetype, "line": actor.tactical_line, "build": actor.build_variant})
		while not game.finished:
			var was_shop: bool = game.shop_open
			game._physics_process(1.0 / 60.0)
			var elapsed: float = game.match_elapsed()
			if was_shop and not game.shop_open:
				phase_start = elapsed
				phase.clear()
				for actor in game.players:
					phase.append({"inventory": actor.inventory.duplicate(), "stats": actor.stats.duplicate()})
			elif not was_shop and (game.shop_open or game.finished):
				for i in range(game.players.size()):
					for id in phase[i].inventory:
						equipment[id].equipped_seconds += elapsed - phase_start
						for metric in ["goals", "tackles", "possession_seconds"]:
							equipment[id][metric] += game.players[i].stats[metric] - phase[i].stats[metric]
				if game.shop_open:
					# Simulated blue coach uses the same available tactic as the red coach.
					game.choose_formation(Formations.opponent_formation(game.score[0] - game.score[1], game.rng))
		var rows: Array = []
		for actor in game.players:
			rows.append({"team": actor.team, "shirt_number": actor.shirt_number, "role": actor.archetype,
				"line": actor.tactical_line, "goalkeeper": actor.goalkeeper, "build": actor.build_variant,
				"stats": actor.stats.duplicate(), "gold": actor.gold, "inventory": actor.inventory.duplicate(),
				"team_purchases": actor.team_purchases.duplicate(), "e_selected": actor.e_selected,
				"e_charges": actor.e_charges.duplicate(), "evolution_times": actor.evolution_times.duplicate()})
		save_json(output, {"round": number, "configuration": batch, "pair": pair + 1, "leg": leg, "seed": seed_value, "kickoff": leg,
			"score": game.score.duplicate(), "seconds": game.match_elapsed(), "overtime": game.overtime_count,
			"starting": starting, "players": rows, "equipment": equipment,
			"purchases": game.purchase_events.duplicate(true), "e_purchases": game.e_purchase_events.duplicate(true),
			"e_casts": game.e_cast_events.duplicate(true), "goals": game.goal_events.duplicate(true),
			"keeper": game.tactics.keeper_events.duplicate(true), "difficulty": game.difficulty, "passes": game.tactics.pass_events.duplicate(true), "q_actions": game.tactics.q_events.duplicate(true), "phases": game.tactics.phase_seconds.duplicate(true),
			"loose_seconds": game.loose_ball_seconds, "team_upgrades": game.team_upgrades.duplicate(true)})
		print("ROUND %02d / 20: %d:%d | %.0fs | OT %d | gear purchases %d | E bought %d / cast %d" % [number,
			game.score[0], game.score[1], game.match_elapsed(), game.overtime_count,
			game.purchase_events.size(), game.e_purchase_events.size(), game.e_cast_events.size()])
		print("TACTICS passes %d | completed %d | Q %d" % [game.tactics.pass_events.size(), game.tactics.pass_events.filter(func(e): return e.result == "complete").size(), game.tactics.q_events.size()])
		print("KEEPER holds %d / lost %d" % [game.tactics.keeper_events.size(), game.tactics.keeper_events.filter(func(e): return e.result == "lost").size()])
		await process_frame
	print("COMPLETED %d..%d in %.1fs" % [first, last, (Time.get_ticks_msec() - started) / 1000.0])
	game.free()
	quit()
