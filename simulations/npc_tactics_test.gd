extends SceneTree
const F = preload("res://scripts/formations.gd")
var checks := 0
var failures := 0
var game: Node3D


func _initialize() -> void:
	call_deferred("run")


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
	print(("PASS: " if ok else "FAIL: ") + label)


func setup() -> void:
	game.rng.seed = 76123
	# Simulation matches preserve their roster; seed the roster as well as decisions.
	game.assign_formation(0, true)
	game.assign_formation(1, true)
	game.start_match()
	game.skip_shop()
	game.tactics.reset(true)
	game.possession_lock = 0.0
	game.carrier = null
	for i in range(game.players.size()):
		var actor = game.players[i]
		actor.human = true
		actor.position = Vector3(-35 + i * 2, 0, 27)
		actor.target = actor.position
		actor.inventory.clear()
		actor.velocity = Vector3.ZERO
		actor.ai_think_wait = 0.4


func step(seconds: float) -> void:
	for frame in range(roundi(seconds * 60)):
		game._physics_process(1.0 / 60)


func run() -> void:
	game = load("res://main.tscn").instantiate()
	game.simulation_mode = true
	root.add_child(game)
	game.set_physics_process(false)
	var sender = game.player
	var receiver = game.players[6]
	var defender = game.players[15]
	# Real human Q, initially back-facing receiver; do not teleport the ball to reception.
	setup()
	sender.position = Vector3(0, 0, 0)
	sender.facing = Vector3.RIGHT
	sender.target = sender.position
	receiver.position = Vector3(15, 0, 2)
	receiver.target = receiver.position
	receiver.facing = Vector3.RIGHT
	receiver.human = false
	game.carrier = sender
	game.player_kick()
	check(not game.tactics.flight.is_empty() and game.tactics.flight.to == receiver, "human Q identifies the teammate along the actual ball trajectory")
	check(receiver.ai_think_wait >= 0.07 and receiver.ai_think_wait < 0.25, "reception reacts quickly but not in the same frame")
	step(0.05)
	check(receiver.facing == Vector3.RIGHT, "receiver cannot read input or instantly turn before reaction")
	step(0.95)
	check(game.tactics.pass_events[0].result == "complete", "back-facing teammate turns and intercepts a real fast human pass")
	check(receiver.position.z < 1.8, "receiver actively moves to meet the pass")
	for distance in [8.0, 18.0, 25.0]:
		for equipped in [false, true]:
			setup()
			sender.position = Vector3.ZERO
			sender.target = sender.position
			sender.facing = Vector3.RIGHT
			if equipped:
				sender.inventory.assign([17])
			receiver.position = Vector3(distance, 0, 1.2)
			receiver.target = receiver.position
			receiver.facing = Vector3.RIGHT
			receiver.human = false
			game.carrier = sender
			game.player_kick()
			step(1.5)
			check(game.tactics.pass_events[0].result == "complete", "actual player pass received at %.0fm, power shoes %s" % [distance, equipped])
	setup()
	sender.position = Vector3(-30, 0, 0)
	sender.target = sender.position
	sender.facing = Vector3.LEFT
	var keeper = game.players[0]
	keeper.position = Vector3(-43, 0, 1.2)
	keeper.target = keeper.position
	keeper.human = false
	keeper.facing = Vector3.LEFT
	game.carrier = sender
	game.player_kick()
	step(1.2)
	check(game.tactics.pass_events[0].result == "complete" and game.tactics.pass_events[0].to == 1 and keeper.position == keeper.constrain_position(keeper.position), "friendly keeper receives a real player backpass without leaving its penalty area")
	# No remote kicks; same reach and height as human Q, with possession protection.
	setup()
	defender.human = false
	defender.tactical_line = F.Line.BACK
	defender.position = Vector3(10, 0, 0)
	defender.target = defender.position
	defender.facing = Vector3.LEFT
	game.ball.position = Vector3(8.7, 0.34, 0)
	game.ball.velocity = Vector3.ZERO
	game.last_touch = sender
	check(game.tactics.can_poke(defender), "a defender can challenge an in-range loose ball without owning it")
	game.ball.position.y = 2.0
	check(not game.tactics.can_poke(defender), "Q cannot challenge a ball above reach")
	game.ball.position = Vector3(5, 0.34, 0)
	check(not game.tactics.can_poke(defender), "Q cannot kick a distant ball")
	game.ball.position = Vector3(8.7, 0.34, 0)
	game.carrier = sender
	game.possession_lock = 0.6
	check(not game.tactics.can_poke(defender), "Q challenge respects the carrier protection window")
	game.carrier = null
	game.possession_lock = 0
	var queued := false
	for trial in range(10):
		if game.tactics.try_poke(defender):
			queued = true
			break
	check(queued and defender.ai_poke and defender.ai_kick_wait > 0, "defender schedules a physical clearance with reaction delay")
	defender.ai_think_wait = 5
	# Delay is real; manually update intent/movement so ordinary ball pickup cannot preempt this isolated kick.
	game._update_ai(0.05)
	check(defender.stats.kicks == 0, "Q intent cannot execute before its reaction delay")
	for frame in range(45):
		game._update_ai(1.0 / 60)
		defender.step(1.0 / 60, [])
		if defender.stats.kicks > 0:
			break
	check(defender.stats.kicks == 1 and game.ball.velocity.x < 0, "defensive Q actually clears the ball toward the opposing half")
	check(game.tactics.q_events[0].kind == "clearance", "clearance is measured separately from a shot")
	# Losing the opportunity cancels the planned action, rather than kicking remotely.
	setup()
	defender.human = false
	defender.position = Vector3(10, 0, 0)
	game.ball.position = Vector3(9, 0.34, 0)
	defender.ai_poke = true
	game._queue_ai_kick(defender, Vector3.LEFT, 27, 0)
	game.ball.position.x = 0
	game._update_ai(0.01)
	check(defender.ai_kick_power == 0 and defender.stats.kicks == 0, "planned Q cancels if the ball moves out of reach")
	check(game.NPCTactics.TUNE.poke_back > game.NPCTactics.TUNE.poke_mid and game.NPCTactics.TUNE.poke_mid > game.NPCTactics.TUNE.poke_front, "position-based Q preference is back > midfield > front")
	# Threatened striker shoots even before the routine dribbling decision timer.
	setup()
	sender.human = false
	sender.tactical_line = F.Line.FRONT
	sender.position = Vector3(25, 0, 0)
	sender.decision_time = 0.8
	defender.position = Vector3(27, 0, 1)
	game.carrier = sender
	game.tactics.attack(sender)
	check(sender.ai_kick_kind == "pressure_shot" and sender.ai_kick_power > 0, "striker under pressure prepares a shot before losing possession")
	# Pass-and-run must move the original passer and actually return the ball.
	setup()
	sender.human = false
	sender.tactical_line = F.Line.FRONT
	sender.position = Vector3(0, 0, 0)
	sender.decision_time = 0
	receiver.position = Vector3(9, 0, 7)
	receiver.target = receiver.position
	receiver.human = false
	defender.position = Vector3(4, 0, -1)
	game.carrier = sender
	game.tactics.attack(sender)
	check(sender.ai_kick_kind == "one_two" and sender.ai_pass_target == receiver, "local pressure triggers a two-player passing combination")
	check(game.tactics.support(sender).x > sender.position.x + 5, "original passer makes a forward run after the pass")
	game.kick_ball(sender, sender.ai_aim_direction, sender.ai_kick_power)
	sender.position = Vector3(8, 0, 0)
	sender.velocity = Vector3.RIGHT * 4
	game.carrier = receiver
	game.tactics.on_control(receiver)
	receiver.decision_time = 0
	game.tactics.attack(receiver)
	check(receiver.ai_kick_kind == "return" and receiver.ai_pass_target == sender, "wall receiver chooses the forward runner for the return pass")
	var original: Vector3 = receiver.ai_aim_direction
	var error: float = receiver.ai_aim_error
	receiver.ai_kick_kind = "pass"
	sender.position.z += 7
	game.tactics.refresh_pass(receiver)
	check(receiver.ai_aim_direction != original and receiver.ai_aim_error == error, "observed receiver movement updates a turning passer's aim without removing aiming error")
	setup()
	sender.human = false
	sender.tactical_line = F.Line.FRONT
	sender.position = Vector3.ZERO
	sender.target = sender.position
	sender.decision_time = 0
	receiver.position = Vector3(9, 0, 7)
	receiver.target = receiver.position
	receiver.human = false
	receiver.ai_think_wait = 10
	defender.position = Vector3(4, 0, -1)
	defender.target = defender.position
	game.carrier = sender
	game.tactics.attack(sender)
	for frame in range(240):
		game._physics_process(1.0 / 60)
		if game.tactics.pass_events.any(func(e): return e.kind == "return" and e.result == "complete"):
			break
	var returns: Array = game.tactics.pass_events.filter(func(e): return e.kind == "return" and e.result == "complete")
	if returns.is_empty() or sender.position.x <= defender.position.x:
		print("WALL FAILURE ", game.tactics.pass_events, " sender ", sender.position, " receiver ", receiver.position, " wall ", game.tactics.walls[0])
	check(not returns.is_empty() and sender.position.x > defender.position.x, "full physical one-two returns the ball to a runner beyond the local defender")
	# Width and distinct box runs, followed by a real low crossing decision.
	for receiver_role in [0, 1, 2, 3, 5]:
		setup()
		sender.human = false
		sender.position = Vector3(37, 0, 20)
		sender.target = sender.position
		sender.decision_time = 0
		receiver.set_archetype(receiver_role)
		receiver.tactical_line = F.Line.FRONT
		receiver.position = Vector3(36, 0, 6)
		receiver.target = receiver.position
		receiver.human = false
		game.carrier = sender
		game.tactics.attack(sender)
		check(sender.ai_kick_kind == "cross" and sender.ai_pass_target == receiver, "wide carrier crosses to receiver role %d" % receiver_role)
		receiver.home.z = 9
		receiver.ai_think_wait = 10
		step(2.0)
		check(not game.tactics.pass_events.is_empty() and game.tactics.pass_events[0].kind == "cross" and game.tactics.pass_events[0].result == "complete", "physical low cross received by role %d" % receiver_role)
	setup()
	game.carrier = sender
	sender.human = false
	sender.position = Vector3(37, 0, 20)
	sender.decision_time = 0
	receiver.tactical_line = F.Line.FRONT
	receiver.position = Vector3(27, 0, 6)
	game.tactics.attack(sender)
	check(sender.ai_kick_kind == "cutback", "deeper passing option produces a cutback rather than an impossible narrow shot")
	var opposite = game.players[7]
	opposite.tactical_line = F.Line.FRONT
	receiver.home.z = -9
	opposite.home.z = 9
	check(game.tactics.support(receiver).z < 0 and game.tactics.support(opposite).z > 0, "box runners occupy distinct near and far lanes")
	setup()
	sender.human = false
	sender.position = Vector3(22, 0, 20)
	sender.decision_time = 0
	receiver.tactical_line = F.Line.BACK
	receiver.home = Vector3(-32, 0, 22)
	receiver.position = Vector3(27, 0, 23)
	receiver.human = false
	game.carrier = sender
	game.tactics.phases[0] = "wide"
	check(game.tactics.support(receiver).x > sender.position.x, "near-side wide back overlaps ahead of the carrier")
	game.tactics.attack(sender)
	check(sender.ai_kick_kind == "overlap" and sender.ai_pass_target == receiver, "wide carrier can feed the fullback who actually overtook it")
	var support_point: Vector3 = game.tactics.support(receiver)
	game.kick_ball(sender, sender.ai_aim_direction, sender.ai_kick_power)
	check(game.tactics.support(receiver) == support_point, "friendly passing flight retains the attacking support shape")
	check(game._defensive_targets(0, Vector3(-30, 0, 0)).is_empty(), "own pass in flight does not falsely trigger a defensive transition")
	step(1.5)
	check(game.tactics.pass_events[0].kind == "overlap" and game.tactics.pass_events[0].result == "complete", "full physical overlap pass reaches the advancing fullback in an open lane")
	game.carrier = sender
	receiver.home.z = -22
	check(game.tactics.support(receiver).x < sender.position.x - 10, "far-side back retains defensive cover instead of joining the overlap")
	# Global phases derive from the actual game state.
	setup()
	game.team_formations = [1, 0]
	game.carrier = sender
	game.tactics.tick(0.1)
	check(game.tactics.phases == ["wide", "build"], "formation distinguishes wide attack from short buildup")
	game.carrier = defender
	defender.human = false
	game.tactics.tick(0.1)
	check(game.tactics.phases[1] == "counter", "winning possession triggers a bounded counterattack phase")
	game.score = [1, 0]
	game.time_left = 60
	game.tactics.tick(0.1)
	check(game.tactics.phases == ["protect", "press"], "late scoreline splits lead protection from urgent pressing")
	check(game.chaser_count(0) == 1 and game.chaser_count(1) == 1, "score-based pressing retains one direct challenger")
	# Closed passing lanes are rejected, even on Normal difficulty.
	setup()
	sender.position = Vector3.ZERO
	receiver.position = Vector3(12, 0, 0)
	defender.position = Vector3(6, 0, 0)
	check(game.tactics.lane_risk(sender, receiver.position) > 10, "passing evaluation penalizes an opponent in the lane")
	defender.position.z = 8
	check(game.tactics.lane_risk(sender, receiver.position) == 0, "an open passing lane is not penalized")
	# A blocked passing lane remains a real interception, not an assigned-receiver magnet.
	setup()
	sender.position = Vector3.ZERO
	sender.facing = Vector3.RIGHT
	sender.target = sender.position
	receiver.position = Vector3(20, 0, 0)
	receiver.target = receiver.position
	receiver.human = false
	defender.position = Vector3(10, 0, 0)
	defender.target = defender.position
	game.carrier = sender
	game.player_kick()
	step(1.0)
	check(game.tactics.pass_events[0].result != "complete", "opponent can still block a player pass before the selected receiver")
	# Supply freezes pending tactics together with actual players and the ball.
	setup()
	sender.position = Vector3.ZERO
	sender.facing = Vector3.RIGHT
	sender.target = sender.position
	receiver.position = Vector3(18, 0, 0)
	receiver.target = receiver.position
	receiver.human = false
	game.carrier = sender
	game.player_kick()
	step(0.15)
	var age: float = game.tactics.flight.age
	var position: Vector3 = game.ball.position
	game.open_shop(0, "test supply", true)
	step(1.0)
	check(game.tactics.flight.age == age and game.ball.position == position, "supply break freezes reception intent and flight together")
	game.skip_shop()
	step(1.0)
	check(game.tactics.pass_events[0].result == "complete", "reception resumes after the supply break")
	game.reset_kickoff(0)
	check(game.tactics.flight.is_empty() and game.tactics.walls[0].is_empty(), "kickoff removes stale receiver and combination intents")
	# A blocked front-facing shot must give way to an available passing lane.
	setup()
	sender.human = false
	sender.position = Vector3(30, 0, 0)
	sender.tactical_line = F.Line.FRONT
	sender.decision_time = 0
	receiver.position = Vector3(25, 0, 10)
	game.carrier = sender
	for i in range(3):
		game.players[12 + i].position = Vector3(35, 0, (i - 1) * 1.3)
	check(game.tactics.shot_option(sender).quality < 0.38, "defenders covering the goal mouth suppress speculative shots")
	game.tactics.attack(sender)
	check(sender.ai_pass_target != null and sender.ai_kick_kind not in ["shot", "pressure_shot"], "blocked attacker chooses an available teammate")
	for i in range(3):
		game.players[12 + i].position.z = 27
	check(game.tactics.shot_option(sender).quality >= 0.38, "a clear scoring opportunity remains shootable")
	# Same-team domains reserve space at execution, with a new threat elsewhere allowed.
	setup()
	var warden = game.players[1]
	var second = game.players[2]
	warden.set_archetype(5)
	second.set_archetype(5)
	warden.position = Vector3(-30, 0, 0)
	second.position = Vector3(-31, 0, 1)
	defender.position = Vector3(-25, 0, 0)
	game.carrier = defender
	var point: Variant = game._ai_domain_target(warden)
	check(point != null and game.use_ability(warden, Vector3.ZERO, point), "first warden can cover the threatening ball carrier")
	check(game._ai_domain_target(second) == null, "second warden holds W while the same threat is already covered")
	game.players[16].position = Vector3(-30, 0, -22)
	point = game._ai_domain_target(second)
	check(point != null and point.distance_to(game.fields[0].position) >= 17, "second warden may cover a separate uncovered threat")
	game.free()
	print("NPC TACTICS: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)
