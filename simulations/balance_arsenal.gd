extends SceneTree
## Thirty games, fifteen mirrored pairs, final configuration and real shop/OT rules.
const Roles = preload("res://scripts/archetypes.gd")
const Gear = preload("res://scripts/equipment.gd")
const ES = preload("res://scripts/purchasable_skills.gd")
const Formations = preload("res://scripts/formations.gd")
const OUTPUT := "res://work/balance-arsenal/"
var first := 1
var last := 30


func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--from="):
			first = int(argument.get_slice("=", 1))
		elif argument.begins_with("--to="):
			last = int(argument.get_slice("=", 1))
	assert(first >= 1 and last <= 30 and first <= last)
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
	var started := Time.get_ticks_msec()
	save_json(OUTPUT + "configuration.json", {"items": Gear.ITEMS, "skills": ES.SKILLS, "npc_builds": Gear.NPC_BUILDS,
		"hero_names": Roles.NAMES, "speed": Roles.SPEED, "cooldown": Roles.COOLDOWN, "duration": Roles.DURATION,
		"domain": {"radius": Roles.DOMAIN_RADIUS, "range": Roles.DOMAIN_RANGE, "slow": 0.3, "seconds": 40, "cooldown": 60},
		"physics_hz": 60, "regulation_seconds": 300, "overtime_seconds": 120, "games": 30,
		"setup": "15 pairs; identical pair seed; mirrored rosters/build routes/kickoff; two of each field hero per side, one keeper; both AI teams adjust formations by score at shops"})
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
		var seed_value := 31100 + pair
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
		save_json(output, {"round": number, "pair": pair + 1, "leg": leg, "seed": seed_value, "kickoff": leg,
			"score": game.score.duplicate(), "seconds": game.match_elapsed(), "overtime": game.overtime_count,
			"starting": starting, "players": rows, "equipment": equipment,
			"purchases": game.purchase_events.duplicate(true), "e_purchases": game.e_purchase_events.duplicate(true),
			"e_casts": game.e_cast_events.duplicate(true), "goals": game.goal_events.duplicate(true),
			"loose_seconds": game.loose_ball_seconds, "team_upgrades": game.team_upgrades.duplicate(true)})
		print("ROUND %02d / 30: %d:%d | %.0fs | OT %d | gear purchases %d | E bought %d / cast %d" % [number,
			game.score[0], game.score[1], game.match_elapsed(), game.overtime_count,
			game.purchase_events.size(), game.e_purchase_events.size(), game.e_cast_events.size()])
		await process_frame
	print("COMPLETED %d..%d in %.1fs" % [first, last, (Time.get_ticks_msec() - started) / 1000.0])
	game.free()
	quit()
