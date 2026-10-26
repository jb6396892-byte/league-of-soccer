extends RefCounted
## Observed-ball reception and coordinated runs. No movement/gold/vision bonuses.
const F = preload("res://scripts/formations.gd")
const TUNE := {
	"receive_delay": 0.09, "receive_turn": 720.0, "trap_angle": 65.0,
	"lane_margin": 2.8, "pass_threshold": 1.0, "pass_lead": 0.28,
	"press_shot_range": 28.0, "poke_back": 0.82, "poke_mid": 0.48, "poke_front": 0.3,
	"poke_reaction": 0.24, "wall_pressure": 5.0, "wall_run": 9.0,
	"cross_start": 30.0, "cross_width": 14.0, "support_gap": 10.5,
	"counter_seconds": 6.0, "return_window": 4.5, "pass_speed": 17.0,
	"protect_seconds": 90.0, "press_seconds": 120.0,
	"keeper_release": 0.2, "keeper_lane": 6.0, "keeper_space": 3.2
}
var game: Node3D
var flight := {}
var walls: Array = [{}, {}]
var pass_events: Array = []
var q_events: Array = []
var phases := ["build", "build"]
var phase_seconds: Array = [{}, {}]
var counter := [0.0, 0.0]
var previous_team := -1
var keeper_hold := {}
var keeper_events: Array = []


func _init(match_node: Node3D) -> void:
	game = match_node


func reset(fresh: bool = false) -> void:
	end_keeper_hold("restart")
	end_flight("restart")
	walls = [{}, {}]
	counter = [0.0, 0.0]
	previous_team = -1
	if fresh:
		pass_events.clear()
		q_events.clear()
		keeper_events.clear()
		phase_seconds = [{}, {}]


func tick(delta: float) -> void:
	if not keeper_hold.is_empty():
		if game.carrier != keeper_hold.actor:
			end_keeper_hold("lost")
		else:
			keeper_events[keeper_hold.index].seconds += delta
	if game.carrier != null:
		var team: int = game.carrier.team
		if previous_team >= 0 and previous_team != team:
			counter[team] = TUNE.counter_seconds
			walls[1 - team].clear()
		previous_team = team
	for team in range(2):
		counter[team] = maxf(0.0, counter[team] - delta)
		var difference: int = game.score[team] - game.score[1 - team]
		phases[team] = "wide" if game.team_formations[team] in [1, 3] else "build"
		if counter[team] > 0.0:
			phases[team] = "counter"
		if difference > 0 and game.time_left < TUNE.protect_seconds:
			phases[team] = "protect"
		elif difference < 0 and game.time_left < TUNE.press_seconds:
			phases[team] = "press"
		phase_seconds[team][phases[team]] = phase_seconds[team].get(phases[team], 0.0) + delta
		if not walls[team].is_empty():
			walls[team].left -= delta
			if walls[team].left <= 0.0:
				walls[team].clear()
	if not flight.is_empty():
		flight.age += delta
		if flight.age > 4.0:
			end_flight("missed")


func end_flight(result: String, receiver: Node3D = null) -> void:
	if flight.is_empty():
		return
	var entry: Dictionary = pass_events[flight.index]
	entry.result = result
	entry.travel_seconds = flight.age
	entry.received_by = receiver.shirt_number if receiver != null else -1
	flight.to.ai_receive_time = 0.0
	flight.clear()


func pressure(actor: Node3D) -> float:
	var nearest := 100.0
	for other in game.players:
		if other.team != actor.team and not other.action_blocked():
			nearest = minf(nearest, actor.position.distance_to(other.position))
	return nearest


func lane_risk(actor: Node3D, point: Vector3) -> float:
	var risk := 0.0
	for other in game.players:
		if other.team == actor.team or other.action_blocked():
			continue
		var nearest := Geometry3D.get_closest_point_to_segment(other.position, actor.position, point)
		var gap: float = other.position.distance_to(nearest)
		if gap < TUNE.lane_margin and nearest.distance_to(actor.position) > 2.0:
			risk += (TUNE.lane_margin - gap) * 7.0
	return risk


func pass_target(actor: Node3D) -> Node3D:
	var attack := 1.0 if actor.team == 0 else -1.0
	var best: Node3D
	var rating: float = TUNE.pass_threshold
	var safe_backpass: bool = phases[actor.team] == "protect" or pressure(actor) < 5.0
	for mate in game.players:
		if mate.team != actor.team or mate == actor or mate.goalkeeper or mate.action_blocked():
			continue
		var distance: float = actor.position.distance_to(mate.position)
		var progress: float = (mate.position.x - actor.position.x) * attack
		if distance < 5.0 or distance > 30.0 or progress < (-14.0 if safe_backpass else -5.0):
			continue
		var value: float = progress * 0.65 - distance * 0.14 + minf(pressure(mate), 8.0) * 0.8
		var risk := lane_risk(actor, mate.position)
		if risk >= 10.0:
			continue
		value -= risk
		value += 4.0 if mate.human else 0.0
		if phases[actor.team] == "wide" and absf(mate.position.z) > 15.0:
			value += 5.0
		if phases[actor.team] == "protect":
			value += minf(pressure(mate), 10.0) - maxf(progress, 0.0) * 0.6
		if value > rating:
			rating = value
			best = mate
	return best


func queue_pass(actor: Node3D, receiver: Node3D, kind: String, point: Vector3) -> void:
	actor.ai_pass_target = receiver
	actor.ai_kick_kind = kind
	var distance: float = actor.position.distance_to(point)
	# Pass launch speed is calibrated after shoe bonuses; powerful shoes must not turn short passes into shots.
	var power: float = clampf(TUNE.pass_speed + distance * 0.22, 17.0, 24.0) / (1.0 + actor.equipment_bonus("kick"))
	game._queue_ai_kick(actor, point - actor.position, power, game.ai_profile(actor).pass_error)


func on_kick(actor: Node3D, direction: Vector3) -> void:
	if not keeper_hold.is_empty() and keeper_hold.actor == actor:
		end_keeper_hold("released", actor.ai_kick_kind)
	end_flight("interrupted")
	var receiver: Node3D = actor.ai_pass_target
	var kind: String = actor.ai_kick_kind
	if not walls[actor.team].is_empty() and walls[actor.team].receiver == actor and kind != "return":
		walls[actor.team].clear()
	if actor.human and not game.is_practice():
		var best := INF
		for mate in game.players:
			if mate == actor or mate.team != actor.team:
				continue
			var offset: Vector3 = mate.position - actor.position
			var along := offset.dot(direction)
			var lateral := (offset - direction * along).length()
			if along > 3.0 and along < 38.0 and lateral < minf(5.0, 1.5 + along * 0.12):
				var cost := lateral + along * 0.06
				if cost < best:
					best = cost
					receiver = mate
		kind = "player"
	if receiver != null:
		game.possession_lock = 0.1
		pass_events.append({"time": game.match_elapsed(), "team": actor.team, "from": actor.shirt_number,
			"to": receiver.shirt_number, "role": actor.archetype, "kind": kind, "result": "pending",
			"distance": actor.position.distance_to(receiver.position), "line": actor.tactical_line})
		flight = {"from": actor, "to": receiver, "index": pass_events.size() - 1, "age": 0.0}
		if not receiver.human:
			receiver.ai_think_wait = minf(receiver.ai_think_wait, TUNE.receive_delay + game.rng.randf_range(0.0, 0.06))
	else:
		q_events.append({"time": game.match_elapsed(), "team": actor.team, "line": actor.tactical_line,
			"role": actor.archetype, "kind": kind, "shirt": actor.shirt_number, "contested": actor.ai_poke})
	actor.ai_pass_target = null
	actor.ai_kick_kind = "shot"


func refresh_pass(actor: Node3D) -> void:
	# A turn takes time. Refresh from a new observation, keeping the same finite aiming error.
	var mate: Node3D = actor.ai_pass_target
	var point: Vector3 = mate.position + mate.velocity * TUNE.pass_lead
	if actor.ai_kick_kind == "through":
		point.x += 2.5 if actor.team == 0 else -2.5
	elif actor.ai_kick_kind == "return" and not walls[actor.team].is_empty():
		point = walls[actor.team].target
	actor.ai_aim_direction = (point - actor.position).normalized().rotated(Vector3.UP, actor.ai_aim_error)


func receive_target(actor: Node3D) -> bool:
	if flight.is_empty() or flight.to != actor or game.carrier != null:
		return false
	var speed := Vector3(game.ball.velocity.x, 0, game.ball.velocity.z)
	var point := Vector3(game.ball.position.x, 0, game.ball.position.z)
	var best := point
	var best_error := INF
	# Earliest reachable point on the observed trajectory, with ground drag approximation.
	for i in range(49):
		var seconds := i * 0.025
		var travel := maxf(0.0, speed.length() * seconds - 2.5 * seconds * seconds)
		var candidate := point + speed.normalized() * travel
		var error: float = actor.position.distance_to(candidate) - actor.move_speed() * seconds - 1.1 * actor.hit_scale()
		if error < best_error:
			best_error = error
			best = candidate
		if error <= 0.0:
			break
	actor.target = actor.constrain_position(best)
	actor.ai_receive_time = 0.55
	actor.ai_receive_direction = (point - actor.position).normalized()
	actor.ai_turn_error = 0.0
	return true


func can_trap(actor: Node3D) -> bool:
	return not flight.is_empty() and flight.to == actor and actor.ai_receive_time > 0.0 and actor.facing.dot(-Vector3(game.ball.velocity.x, 0, game.ball.velocity.z).normalized()) >= cos(deg_to_rad(TUNE.trap_angle))


func cushion(actor: Node3D) -> bool:
	if flight.is_empty() or flight.to != actor or actor.ai_receive_time <= 0.0 or flight.get("cushioned", false):
		return false
	# A close pass may arrive while turning. Take a loose first touch, never grant remote possession.
	flight.cushioned = true
	game.ball.velocity = game.ball.velocity.normalized() * minf(game.ball.velocity.length() * 0.2, 4.5)
	game.ball.velocity.y = 0.5
	game.possession_lock = 0.1
	return true


func on_control(actor: Node3D, saved: bool = false) -> void:
	end_keeper_hold("lost")
	if not flight.is_empty():
		var from_team: int = flight.from.team
		var intended: bool = flight.to == actor
		var return_pass: bool = pass_events[flight.index].kind == "return"
		end_flight("complete" if intended else ("team_recovery" if actor.team == from_team else "intercepted"), actor)
		if intended:
			actor.decision_time = 0.22
			if return_pass:
				walls[from_team].clear()
		else:
			walls[from_team].clear()
	if actor.goalkeeper:
		# A caught ball ends the dive: recovering to distribute is quicker than a missed save.
		actor.kick_cooldown = minf(actor.kick_cooldown, TUNE.keeper_release)
		actor.save_time = 0.0
		actor.ai_save_wait = -1.0
		actor.decision_time = TUNE.keeper_release
		actor.ai_think_wait = minf(actor.ai_think_wait, TUNE.keeper_release)
		if not actor.human:
			actor.target = actor.position
		keeper_events.append({"team": actor.team, "time": game.match_elapsed(), "saved": saved,
			"seconds": 0.0, "result": "holding", "kind": ""})
		keeper_hold = {"actor": actor, "index": keeper_events.size() - 1}


func end_keeper_hold(result: String, kind: String = "") -> void:
	if keeper_hold.is_empty():
		return
	keeper_events[keeper_hold.index].result = result
	keeper_events[keeper_hold.index].kind = kind
	keeper_hold.clear()


func keeper_distribute(actor: Node3D) -> void:
	actor.target = actor.position
	# Plan and turn during recovery; execution still waits for both the timer and alignment.
	actor.ai_kick_wait = maxf(actor.ai_kick_wait, actor.decision_time)
	var attack := 1.0 if actor.team == 0 else -1.0
	var best: Node3D
	var rating := -INF
	for mate in game.players:
		if mate.team != actor.team or mate == actor or mate.goalkeeper or mate.action_blocked():
			continue
		var offset: Vector3 = mate.position - actor.position
		var distance := offset.length()
		var risk := lane_risk(actor, mate.position)
		var space := pressure(mate)
		for other in game.players:
			if other.team != actor.team or other == actor or other == mate or other.action_blocked():
				continue
			var nearest := Geometry3D.get_closest_point_to_segment(other.position, actor.position, mate.position)
			var reach: float = 1.2 * other.hit_scale() * (1.0 + other.equipment_bonus("pickup"))
			if nearest.distance_to(actor.position) > 2.0 and other.position.distance_to(nearest) < reach + 0.3:
				risk += 8.0
		if distance < 6.0 or distance > 32.0 or offset.x * attack < 3.0 or risk > TUNE.keeper_lane or space < TUNE.keeper_space:
			continue
		var value: float = minf(space, 10.0) * 1.5 - risk * 2.0 - distance * 0.35 - actor.facing.angle_to(offset.normalized()) * 2.0
		if value > rating:
			rating = value
			best = mate
	if best != null:
		queue_pass(actor, best, "keeper_outlet", best.position + best.velocity * TUNE.pass_lead)
		return
	# No safe short outlet: clear diagonally beyond the press, never wait for a perfect pass.
	var point := actor.position + Vector3(attack * 24, 0, 18)
	var alternate := actor.position + Vector3(attack * 24, 0, -18)
	if lane_risk(actor, alternate) < lane_risk(actor, point):
		point = alternate
	actor.ai_pass_target = null
	actor.ai_kick_kind = "keeper_clear"
	game._queue_ai_kick(actor, point - actor.position, 31.0 / (1.0 + actor.equipment_bonus("kick")), game.ai_profile(actor).pass_error)


func can_poke(actor: Node3D) -> bool:
	if actor.goalkeeper or actor.kick_cooldown > 0.0 or actor.action_blocked() or actor.charging or actor.dash_remaining > 0:
		return false
	if game.carrier != null and game.carrier.team == actor.team:
		return false
	if game.carrier != null and game.possession_lock > 0.0:
		return false
	if not flight.is_empty() and flight.from.team == actor.team:
		return false
	var flat := Vector3(game.ball.position.x, 0, game.ball.position.z)
	return actor.position.distance_to(flat) <= 1.85 * actor.hit_scale() and game.ball.position.y <= 1.3 * actor.hit_scale()


func shot_option(actor: Node3D) -> Dictionary:
	var attack := 1.0 if actor.team == 0 else -1.0
	var centre := Vector3(48 * attack, 0, 0)
	var distance: float = actor.position.distance_to(centre)
	var best := {"quality": 0.0, "point": centre}
	if distance > 27 or actor.position.x * attack < 18:
		return best
	var mouth: float = (centre + Vector3(0, 0, 5) - actor.position).angle_to(centre - Vector3(0, 0, 5) - actor.position)
	if mouth < 0.22:
		return best
	var speed: float = 27 * (1.0 + actor.equipment_bonus("kick"))
	for z in [-3.8, -1.9, 0.0, 1.9, 3.8]:
		var point := Vector3(50 * attack, 0, z)
		var quality: float = 0.95 - distance * 0.019 + minf(mouth, 0.8) * 0.25
		for other in game.players:
			if other.team == actor.team or other.action_blocked():
				continue
			var along: Vector3 = Geometry3D.get_closest_point_to_segment(other.position, actor.position, point)
			var travel: float = actor.position.distance_to(along) / speed
			if travel < 0.06 or (other.position - actor.position).dot(point - actor.position) < 0:
				continue
			var reach: float = other.hit_scale() * (1.2 if other.goalkeeper else 0.85)
			reach += other.move_speed() * maxf(0.0, travel - 0.22) * (0.45 if other.goalkeeper else 0.25)
			var gap: float = other.position.distance_to(along)
			if gap < reach:
				quality -= 0.65 * (1.0 - gap / reach) + 0.25
		if quality > best.quality:
			best = {"quality": quality, "point": point}
	return best


func try_poke(actor: Node3D) -> bool:
	if not can_poke(actor):
		return false
	var chance: float = [0.0, TUNE.poke_back, TUNE.poke_mid, TUNE.poke_front][actor.tactical_line]
	if game.rng.randf() >= chance:
		return false
	var attack := 1.0 if actor.team == 0 else -1.0
	var shot := shot_option(actor)
	var in_range: bool = shot.quality >= 0.38
	if not in_range and actor.tactical_line == F.Line.FRONT and game.goal_threat(actor.team, actor.position) < 0.3:
		return false
	var aim: Vector3 = shot.point if in_range else actor.position + Vector3(attack * 22, 0, 12 if actor.position.z >= 0 else -12)
	actor.ai_kick_kind = "volley" if in_range else "clearance"
	actor.ai_poke = true
	actor.ai_kick_wait = TUNE.poke_reaction * (1.5 if game.ai_difficulty(actor.team) == 0 else 1.0)
	game._queue_ai_kick(actor, aim - actor.position, 27.0, game.ai_profile(actor).shot_error)
	return true


func attack(actor: Node3D) -> void:
	if actor.goalkeeper:
		keeper_distribute(actor)
		return
	var sign_x := 1.0 if actor.team == 0 else -1.0
	var goal := Vector3(sign_x * 48.0, 0, 0)
	var near: float = pressure(actor)
	var wide: bool = absf(actor.position.z) > TUNE.cross_width and actor.position.x * sign_x > 12.0
	actor.target = Vector3(sign_x * (40.0 if wide else 45.0), 0, actor.position.z if wide else actor.position.z * 0.65)
	var wall: Dictionary = walls[actor.team]
	if not wall.is_empty() and wall.receiver == actor and near > 2.5:
		actor.target = actor.position
		actor.decision_time = minf(actor.decision_time, 0.12)
	if actor.kick_cooldown > 0.0 or actor.charging:
		return
	var urgent: bool = actor.tactical_line == F.Line.FRONT and near < 3.2 and absf(actor.position.z) < TUNE.cross_width and actor.position.distance_to(goal) < TUNE.press_shot_range
	if actor.decision_time > 0.0 and not urgent:
		return
	actor.decision_time = game.rng.randf_range(0.55, 0.9)
	actor.ai_pass_target = null
	actor.ai_kick_kind = "shot"
	if not wall.is_empty() and wall.receiver == actor and wall.runner.position.distance_to(actor.position) > 4.0:
		var runner: Node3D = wall.runner
		var point: Vector3 = wall.target
		if runner.position.distance_to(point) < 4.0 and lane_risk(actor, point) < 6.0 and point.x * sign_x > actor.position.x * sign_x - 3:
			queue_pass(actor, runner, "return", point)
			return
	if wide and actor.position.x * sign_x >= TUNE.cross_start:
		var best: Node3D
		var best_score := -INF
		for mate in game.players:
			if mate.team != actor.team or mate == actor or mate.goalkeeper or absf(mate.position.z) > 13.0:
				continue
			var forward: float = mate.position.x * sign_x
			if forward < 20 or forward > 44:
				continue
			var value: float = 12.0 - absf(forward - 35.0) + minf(pressure(mate), 6.0) - lane_risk(actor, mate.position)
			if value > best_score:
				best_score = value
				best = mate
		if best != null and best_score > -4.0:
			queue_pass(actor, best, "cutback" if (actor.position.x - best.position.x) * sign_x > 5 else "cross", best.position + best.velocity * TUNE.pass_lead)
			return
	var shot := shot_option(actor)
	var mate := pass_target(actor)
	var better_pass := false
	if mate != null:
		better_pass = shot_option(mate).quality > shot.quality + 0.15 and lane_risk(actor, mate.position) < 6.0
	if shot.quality >= 0.38 and not better_pass and not wide:
		actor.ai_kick_kind = "pressure_shot" if urgent else "shot"
		game._queue_ai_kick(actor, shot.point - actor.position, 27.0, game.ai_profile(actor).shot_error)
		return
	if wide and phases[actor.team] == "wide" and actor.position.x * sign_x < 38:
		for back in game.players:
			if back.team != actor.team or back == actor or back.tactical_line != F.Line.BACK or back.action_blocked():
				continue
			var ahead: float = (back.position.x - actor.position.x) * sign_x
			if back.position.z * actor.position.z <= 0 or absf(back.home.z) < 18 or actor.position.distance_to(back.position) > 16 or ahead < -6 or ahead > 12:
				continue
			if ahead > 1.5 and lane_risk(actor, back.position) < 6:
				queue_pass(actor, back, "overlap", back.position + back.velocity * TUNE.pass_lead)
				return
			if near > 6 and back.target.x * sign_x > actor.position.x * sign_x + 2:
				# Briefly carry inside to let the supporting fullback run past on the outside.
				actor.target = actor.position + Vector3(sign_x * 1.5, 0, -signf(actor.position.z) * 1.5)
				return
	# Give wide runners time to reach the byline instead of passing immediately on every think tick.
	if wide and actor.position.x * sign_x < TUNE.cross_start and near > 3.5 and phases[actor.team] != "protect":
		return
	if mate == null:
		return
	var progress: float = (mate.position.x - actor.position.x) * sign_x
	var point: Vector3 = mate.position + mate.velocity * TUNE.pass_lead
	var kind := "pass"
	if progress < -2:
		kind = "recycle"
	elif near < TUNE.wall_pressure and progress < TUNE.wall_run + 1.0 and actor.position.distance_to(mate.position) < 18.0 and not actor.goalkeeper and actor.tactical_line != F.Line.BACK and walls[actor.team].is_empty():
		kind = "one_two"
		walls[actor.team] = {"runner": actor, "receiver": mate, "target": actor.position + Vector3(sign_x * TUNE.wall_run, 0, -signf(actor.position.z) * 3), "left": TUNE.return_window}
	elif progress > 8.0 and mate.tactical_line == F.Line.FRONT:
		kind = "through"
		point += Vector3(sign_x * 2.5, 0, 0)
	elif absf(mate.position.z) > 16 and mate.tactical_line == F.Line.BACK:
		kind = "overlap"
	queue_pass(actor, mate, kind, point)


func support(actor: Node3D) -> Vector3:
	var owner: Node3D = game.carrier
	if owner == null and not flight.is_empty() and flight.from.team == actor.team:
		owner = flight.from
	var sign_x := 1.0 if actor.team == 0 else -1.0
	var wall: Dictionary = walls[actor.team]
	if not wall.is_empty() and wall.runner == actor:
		return actor.constrain_position(wall.target)
	var shift := clampf(game.ball.position.x * sign_x * 0.42 + 10, -16.0, 25.0) * sign_x
	var point: Vector3 = actor.home + Vector3(shift, 0, game.ball.position.z * 0.12)
	if owner == null or owner.team != actor.team:
		return actor.constrain_position(point)
	var phase: String = phases[actor.team]
	if actor.tactical_line == F.Line.BACK:
		# Only the near-side wide back overlaps; central and far-side backs retain cover.
		if phase == "wide" and absf(actor.home.z) > 18 and actor.home.z * owner.position.z > 0 and absf(owner.position.z) > 10:
			point = Vector3(clampf(owner.position.x * sign_x + 8, -26, 38) * sign_x, 0, signf(actor.home.z) * 23)
		else:
			point.x = minf(point.x * sign_x, owner.position.x * sign_x - 12) * sign_x
	elif actor.tactical_line == F.Line.FRONT:
		if absf(owner.position.z) > TUNE.cross_width and owner.position.x * sign_x > 18:
			# Near and far posts remain separate, allowing a real low cross.
			point = Vector3(sign_x * 36, 0, signf(actor.home.z + 0.01) * 6)
		else:
			point.x = clampf(owner.position.x * sign_x + (14 if phase == "counter" else 10), -5, 41) * sign_x
			point.z = actor.home.z * (1.35 if phase == "wide" else 0.8)
	else:
		var side := signf(actor.home.z + 0.01)
		point.x = clampf(owner.position.x * sign_x + (5 if phase == "counter" else -4), -27, 29) * sign_x
		point.z = clampf(owner.position.z + side * TUNE.support_gap, -22, 22)
		if phase == "wide":
			point.z = side * 22
		if absf(owner.position.z) > TUNE.cross_width and owner.position.x * sign_x > 26:
			point = Vector3(sign_x * 27, 0, side * 9)
	if phase == "protect" and actor.tactical_line != F.Line.BACK:
		point.x -= sign_x * 5
	return actor.constrain_position(point)
