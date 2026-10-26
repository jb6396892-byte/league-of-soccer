extends SceneTree
## Evolution and team-upgrade campaign: one two-match block, then tune before the next block.
## godot --headless --path . --script res://simulations/balance_evolution.gd -- --batch=1

const Roles = preload("res://scripts/archetypes.gd")
const Gear = preload("res://scripts/equipment.gd")
var batch := 1


func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--batch="):
			batch = int(argument.get_slice("=", 1))
	if batch < 1 or batch > 5:
		printerr("--batch must be 1 through 5 (two matches each)")
		quit(1)
		return
	call_deferred("run")


func summarize(rows: Array) -> Array:
	var totals: Array = []
	var held_seconds := 0.0
	for row in rows:
		held_seconds += row.stats.possession_seconds
	for kind in range(Roles.NAMES.size()):
		var total := {"name": Roles.NAMES[kind], "appearances": 0, "outfield_appearances": 0, "outfield": {}}
		for metric in rows[0].stats:
			total[metric] = 0.0
			total.outfield[metric] = 0.0
		for row in rows:
			if row.role != kind:
				continue
			total.appearances += 1
			if not row.goalkeeper:
				total.outfield_appearances += 1
			for metric in row.stats:
				total[metric] += row.stats[metric]
				if not row.goalkeeper:
					total.outfield[metric] += row.stats[metric]
		total.possession_percent = total.possession_seconds / held_seconds * 100.0
		total.outfield_tackles_per_appearance = total.outfield.tackles / max(1, total.outfield_appearances)
		total.outfield_possession_seconds_per_appearance = total.outfield.possession_seconds / max(1, total.outfield_appearances)
		total.outfield_goals_per_appearance = total.outfield.goals / max(1, total.outfield_appearances)
		totals.append(total)
	return totals


func run() -> void:
	var game = load("res://main.tscn").instantiate()
	game.simulation_mode = true
	root.add_child(game)
	game.set_physics_process(false)
	var started_at := Time.get_ticks_msec()
	var games: Array = []
	var all_rows: Array = []
	# Across each mirrored pair every field role has two forward appearances.
	var field_roles: Array = []
	for i in range(20):
		field_roles.append((i + batch - 1) % 4)
	var roster: Array = []
	var builds: Array = []
	var role_counts := [0, 0, 0, 0, 0]
	for i in range(22):
		if i % 11 == 0:
			roster.append(Roles.Kind.KEEPER)
		else:
			roster.append(field_roles.pop_back())
		var kind: int = roster.back()
		builds.append((role_counts[kind] + batch - 1) % 3)
		role_counts[kind] += 1
	for leg in range(2):
		var round_number := (batch - 1) * 2 + leg + 1
		var seed_value := 10100 + round_number - 1
		game.rng.seed = seed_value
		for i in range(22):
			game.players[i].archetype = roster[i if leg == 0 else (i + 11) % 22]
		game.start_match()
		for i in range(22):
			game.players[i].build_variant = builds[i if leg == 0 else (i + 11) % 22]
		game.reset_kickoff(leg)
		game.open_shop(leg, "模拟赛前购买")
		var items: Array = []
		for item in Gear.ITEMS:
			items.append({"name": item.name, "buyers": 0, "equipped_seconds": 0.0,
				"goals": 0, "own_goals": 0, "tackles": 0, "interceptions": 0,
				"possession_seconds": 0.0, "casts": 0, "gold_earned": 0, "stuns": 0, "stun_seconds": 0.0, "saves": 0, "save_attempts": 0})
		var purchases: Array = []
		var phase: Array = []
		var phase_start := 0.0
		var purchased: Array = []
		for actor in game.players:
			purchased.append([])
		while not game.finished:
			var was_shop: bool = game.shop_open
			game._physics_process(1.0 / 60.0)
			var active_time: float = game.MATCH_DURATION - game.time_left
			if was_shop and not game.shop_open:
				phase_start = active_time
				phase.clear()
				for i in range(game.players.size()):
					var actor = game.players[i]
					phase.append({"inventory": actor.inventory.duplicate(), "stats": actor.stats.duplicate()})
					for item_id in actor.inventory:
						if item_id not in purchased[i]:
							purchased[i].append(item_id)
							items[item_id].buyers += 1

			elif not was_shop and (game.shop_open or game.finished):
				for i in range(game.players.size()):
					for item_id in phase[i].inventory:
						items[item_id].equipped_seconds += active_time - phase_start
						for metric in ["goals", "own_goals", "tackles", "interceptions", "possession_seconds", "casts", "gold_earned", "stuns", "stun_seconds", "saves", "save_attempts"]:
							items[item_id][metric] += game.players[i].stats[metric] - phase[i].stats[metric]
		purchases = game.purchase_events.duplicate(true)
		for purchase in purchases:
			if Gear.ITEMS[purchase.item].has("team_upgrade"):
				items[purchase.item].buyers += 1
		var rows: Array = []
		for actor in game.players:
			rows.append({"team": actor.team, "shirt_number": actor.shirt_number,
				"role": actor.archetype, "goalkeeper": actor.goalkeeper,
				"stats": actor.stats.duplicate(), "gold": actor.gold,
				"inventory": actor.inventory.duplicate(), "build_variant": actor.build_variant,
				"evolution_times": actor.evolution_times.duplicate(), "team_purchases": actor.team_purchases.duplicate(),
				"final_throw_radius": actor.throw_radius(), "final_throw_speed": actor.throw_speed()})
		all_rows.append_array(rows)
		var totals := summarize(rows)
		games.append({"round": round_number, "seed": seed_value, "kickoff_team": leg,
			"score": game.score.duplicate(), "goal_events": game.goal_events.duplicate(true),
			"players": rows, "roles": totals, "loose_ball_seconds": game.loose_ball_seconds,
			"equipment": items, "purchases": purchases, "team_upgrades": game.team_upgrades.duplicate(true),
			"team_speed": [game.team_speed(0), game.team_speed(1)]})
		print("ROUND %d: %d:%d" % [round_number, game.score[0], game.score[1]])
		for total in totals:
			print("  %s goals=%d tackles=%d interceptions=%d possession=%.1f%% (%.1fs)" % [
				total.name, total.goals, total.tackles, total.interceptions,
				total.possession_percent, total.possession_seconds])
		print("TEAM UPGRADES %s SPEED %s" % [game.team_upgrades, [game.team_speed(0), game.team_speed(1)]])
		for actor in game.players:
			if actor.archetype == Roles.Kind.STRIKER:
				print("FLAG team=%d number=%d hits=%d thresholds=%s" % [actor.team, actor.shirt_number, actor.stats.stuns, actor.evolution_times])
		for item in items:
			print("  ITEM %s buyers=%d minutes=%.1f goals=%d tackles=%d held=%.1fs" % [
				item.name, item.buyers, item.equipped_seconds / 60, item.goals, item.tackles, item.possession_seconds])
		await process_frame
	var result := {"batch": batch, "games": games, "totals": summarize(all_rows),
		"seconds_per_game": 300, "physics_hz": 60,
		"parameters": {"speed": Roles.SPEED, "hit_scale": Roles.HIT_SCALE,
			"duration": Roles.DURATION, "cooldown": Roles.COOLDOWN,
			"sprint_multiplier": Roles.SPRINT_MULTIPLIER,
			"slow_radius": Roles.SLOW_RADIUS, "slow_multiplier": Roles.SLOW_MULTIPLIER,
			"charge_duration": Roles.CHARGE_DURATION, "dash_speed": Roles.DASH_SPEED,
			"ai_charge_min_seconds": Roles.CHARGE_DURATION * Roles.AI_CHARGE_MIN_FRACTION,
			"dash_distance": [Roles.DASH_MIN_DISTANCE, Roles.DASH_MAX_DISTANCE],
			"throw_range": Roles.THROW_RANGE, "throw_speed": Roles.THROW_SPEED,
			"throw_radius": Roles.THROW_RADIUS, "throw_windup": Roles.THROW_WINDUP,
			"stun_seconds": Roles.STUN_SECONDS, "hit_width_growth": 0, "hit_speed_growth": 0,
			"stun_upgrade_hits": 0, "stun_upgrade_bonus": 0,
			"mobile_throw_hits": 0, "team_gain": Gear.TEAM_SPEED_GAIN, "team_loss": Gear.TEAM_SPEED_LOSS,
			"keeper_radius": Roles.KEEPER_SLOW_RADIUS, "keeper_slow": Roles.KEEPER_SLOW_MULTIPLIER,
			"save_reach": Roles.SAVE_REACH, "save_window": Roles.SAVE_WINDOW, "save_cooldown": Roles.SAVE_COOLDOWN,
			"items": Gear.ITEMS, "npc_builds": Gear.NPC_BUILDS,
			"economy": {"start": Gear.START_GOLD, "tackle": Gear.TACKLE_GOLD,
				"intercept": Gear.INTERCEPT_GOLD, "stun": Gear.STUN_GOLD, "goal": Gear.GOAL_GOLD, "team_goal": Gear.TEAM_GOAL_GOLD,
				"possession": Gear.POSSESSION_GOLD, "stipend": Gear.STIPEND_GOLD}},
		"elapsed_seconds": (Time.get_ticks_msec() - started_at) / 1000.0}
	var output := "res://work/balance-evolution/balance-batch-%02d.json" % batch
	var file := FileAccess.open(output, FileAccess.WRITE)
	file.store_string(JSON.stringify(result, "\t"))
	file.close()
	for total in result.totals:
		print("BLOCK %d %s: outfield n=%d goals=%.3f tackles=%.2f possession=%.2fs per appearance" % [
			batch, total.name, total.outfield_appearances, total.outfield_goals_per_appearance,
			total.outfield_tackles_per_appearance, total.outfield_possession_seconds_per_appearance])
	print("SAVED " + output)
	game.free()
	quit()
