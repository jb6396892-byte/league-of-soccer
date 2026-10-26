extends RefCounted
## Self-contained snapshots: a lost packet never loses an equipment/skill change.
const ACTOR_KEYS := ["position", "velocity", "facing", "target", "kick_cooldown", "ability_time", "ability_cooldown", "slow_multiplier", "charging", "charge_time", "dash_remaining", "dash_direction", "dash_flash", "stun_time", "throw_windup", "save_time", "e_cooldown", "e_boost_time", "e_boost_multiplier", "e_immunity_time", "gait", "kick_pose", "gold", "inventory", "e_selected", "e_charges", "team_speed_multiplier", "tactical_line", "home", "human"]
const GAME_KEYS := ["score", "time_left", "overtime_count", "goal_pause", "shop_open", "shop_title", "supply_shop", "supply_clock", "timeout_tokens", "timeout_team", "kickoff_team", "team_upgrades", "team_formations", "finished", "announcement", "announcement_time", "shots"]
const STATS := ["goals", "tackles", "casts", "e_casts", "stuns"]
const FIELD_KEYS := ["position", "team", "radius", "remaining", "multiplier", "title"]
const SHOT_KEYS := ["position", "direction", "windup", "remaining", "radius", "speed", "stun_seconds", "mobile_cast"]

static func values(object: Object, keys: Array) -> Array:
	var result: Array = []
	for key in keys:
		result.append(object.get(key))
	return result

static func capture(game: Node3D) -> Dictionary:
	var actors: Array = []
	for actor in game.players:
		var stats: Array = []
		for key in STATS:
			stats.append(actor.stats[key])
		actors.append([actor.archetype, values(actor, ACTOR_KEYS), stats])
	var effects: Array = []
	for group in [game.fields, game.projectiles]:
		var batch: Array = []
		for effect in group:
			batch.append([effect.get_instance_id(), game.players.find(effect.source), values(effect, FIELD_KEYS if group == game.fields else SHOT_KEYS)])
		effects.append(batch)
	return {"actors": actors, "game": values(game, GAME_KEYS), "ball": [game.ball.position, game.ball.velocity], "carrier": game.players.find(game.carrier), "effects": effects}

static func apply(game: Node3D, state: Dictionary, first: bool) -> void:
	var previous_shots: int = game.shots
	var previous_score: Array = game.score.duplicate()
	for i in range(GAME_KEYS.size()):
		game.set(GAME_KEYS[i], state.game[i])
	if not first and not game.simulation_mode:
		if game.shots > previous_shots:
			game.kick_sound.play()
		if game.score != previous_score:
			game.goal_scored.emit(0 if game.score[0] > previous_score[0] else 1)
	for i in range(game.players.size()):
		var actor = game.players[i]
		var row: Array = state.actors[i]
		var old_position: Vector3 = actor.position
		var old_target: Vector3 = actor.target
		var old_inventory: Array = actor.inventory.duplicate()
		var old_role: int = actor.archetype
		actor.archetype = row[0]
		for j in range(ACTOR_KEYS.size()):
			# Assignment retains typed Array[int] inventories.
			if ACTOR_KEYS[j] == "inventory":
				actor.inventory.assign(row[1][j])
			else:
				actor.set(ACTOR_KEYS[j], row[1][j])
		for j in range(STATS.size()):
			actor.stats[STATS[j]] = row[2][j]
		if actor.archetype != old_role or actor.inventory != old_inventory:
			actor.refresh_equipment()
		actor.set_meta("network_position", actor.position)
		if not first and game.is_playing() and old_position.distance_to(actor.position) < 3.0:
			if actor == game.player:
				actor.position = old_position.lerp(actor.position + actor.velocity * 0.04, 0.35)
				if game.net.move_sequence > game.net.move_ack:
					actor.target = old_target
			else:
				actor.position = old_position
	game.carrier = game.players[state.carrier] if state.carrier >= 0 else null
	game.ball.velocity = state.ball[1]
	game.ball.set_meta("network_position", state.ball[0])
	if first or not game.is_playing() or game.ball.position.distance_to(state.ball[0]) > 5.0:
		game.ball.position = state.ball[0]
	for kind in range(2):
		var group: Array = game.fields if kind == 0 else game.projectiles
		var keys: Array = FIELD_KEYS if kind == 0 else SHOT_KEYS
		var live: Array = []
		for row in state.effects[kind]:
			live.append(row[0])
			var found: Array = group.filter(func(e): return e.get_meta("network_id", -1) == row[0])
			var effect: Node3D = found[0] if not found.is_empty() else (game.AreaField.new() if kind == 0 else game.SkillProjectile.new())
			effect.source = game.players[row[1]]
			for j in range(keys.size()):
				effect.set(keys[j], row[2][j])
			if found.is_empty():
				effect.visuals_enabled = not game.simulation_mode
				effect.set_meta("network_id", row[0])
				game.add_child(effect)
				group.append(effect)
			if kind == 0:
				effect.update_label()
			elif effect.windup <= 0.0:
				effect.show_flight()
		for effect in group.duplicate():
			if effect.get_meta("network_id") not in live:
				group.erase(effect)
				effect.free()

static func render(game: Node3D, delta: float) -> void:
	for actor in game.players:
		if actor == game.player and game.is_playing():
			# Only locomotion is predicted. Ball possession, kicks, skills and money stay authoritative.
			actor.step(delta, game.players)
		else:
			actor.position = actor.position.lerp(actor.get_meta("network_position", actor.position), minf(1.0, delta * 20.0))
			actor.gait += actor.velocity.length() * delta * 1.7
			if actor.visuals_enabled:
				actor.animate(delta)
	game.ball.position = game.ball.position.lerp(game.ball.get_meta("network_position", game.ball.position), minf(1.0, delta * 25.0))
	game.ball.update_visual(delta)
