extends SceneTree
const F = preload("res://scripts/formations.gd")
const Gear = preload("res://scripts/equipment.gd")
var game: Node3D
var checks := 0
var failures := 0


func _initialize() -> void:
	call_deferred("run")


func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
	print(("PASS: " if ok else "FAIL: ") + message)


func run() -> void:
	game = load("res://main.tscn").instantiate()
	game.simulation_mode = true
	root.add_child(game)
	game.set_physics_process(false)
	game.rng.seed = 20261021
	game.start_match()
	var actor = game.player
	actor.human = true
	actor.archetype = 3
	for formation in range(5):
		check(game.choose_formation(formation), "shop can select formation %s" % F.NAMES[formation])
		game.assign_formation(0, true)
		var counts := [0, 0, 0, 0]
		var homes: Array = []
		for p in game.players.filter(func(a): return a.team == 0):
			counts[p.tactical_line] += 1
			homes.append(p.home)
		check(counts.slice(1) == F.COUNTS[formation] and counts[0] == 1 and homes.size() == 11, "formation has correct line counts and one keeper")
		check(actor.tactical_line == F.Line.BACK and actor.archetype == 3, "controlled flag gets a defensive position without changing hero")
		check(homes.all(func(p): return p.x < 0 and absf(p.z) <= 22), "all starting positions stay in own half")
	for line in [F.Line.BACK, F.Line.MID, F.Line.FRONT]:
		var fits := 0
		for i in range(300):
			if F.PREFERRED_LINE[F.random_hero(line, game.rng)] == line:
				fits += 1
		check(fits > 180 and fits < 280, "line %d weighted generation prefers suitable heroes but allows mixing" % line)
	actor.inventory.append(10)
	actor.refresh_equipment()
	actor.stats.stuns = 8
	actor.gold = 1720
	actor.ability_cooldown = 7
	var identity = actor
	game.choose_formation(2)
	check(game.player == identity and actor.inventory == [10] and actor.gold == 1720 and actor.stats.stuns == 8 and actor.ability_cooldown == 7, "formation changes preserve player identity, equipment, wallet, growth and cooldown")
	game.paused = true
	check(not game.choose_formation(4), "paused shop cannot change formation")
	game.paused = false
	game.skip_shop()
	check(not game.choose_formation(4), "active play cannot change formation")
	check(game.carrier.tactical_line == F.Line.FRONT and not game.carrier.goalkeeper and game.carrier != actor, "a forward takes kickoff while controlled defender stays in position")
	check(actor.position == actor.home, "new formation takes effect at kickoff")
	for difference in [-3, -1, 0, 1, 3]:
		game.score = [3, 3 + difference]
		game.time_left = 250
		game.open_shop(0, "test")
		var selected: int = game.team_formations[1]
		var allowed: Array = { -3: [2], -1: [1, 3], 0: [0, 1, 3], 1: [0, 4], 3: [4] }[difference]
		check(selected in allowed, "opponent selects score-appropriate formation at difference %d" % difference)
		check(game.players.filter(func(p): return p.team == 1 and p.tactical_line == F.Line.BACK).size() == F.COUNTS[selected][0], "opponent lineup follows selected formation")
	# Score rewards use the deficit BEFORE the goal and both teams use the same rule.
	for team in range(2):
		var scorer = game.players[9 + team * 11]
		var teammate = game.players[1 + team * 11]
		for deficit in [0, 1, 3]:
			game.score = [0, 0]
			game.score[1 - team] = deficit
			var before: int = scorer.gold
			var mate_before: int = teammate.gold
			game.last_touch = scorer
			game.ball.position = Vector3(48.5 if team == 0 else -48.5, 0.34, 0)
			game._check_boundaries()
			var multiplier: float = 1.0 + deficit * 0.25
			check(scorer.gold == before + roundi(360 * multiplier) and teammate.gold == mate_before + roundi(60 * multiplier), "team %d trailing %d gets scorer and team comeback gold" % [team, deficit])
			check(game.goal_events.back().reward_multiplier == multiplier and game.comeback_multiplier(team) == 1.0 + maxi(0, deficit - 1) * 0.25, "reward is recorded before gap closes and next bounty decreases")
	game.score = [0, 3]
	var teammate = game.players[1]
	var before: int = teammate.gold
	game.last_touch = game.players[20]
	game.ball.position = Vector3(48.5, 0.34, 0)
	game._check_boundaries()
	check(teammate.gold == before + 60 and game.goal_events.back().reward_multiplier == 1, "own goals award base team gold without comeback bonus")
	check_pressure()
	game.start_match()
	actor.gold = 2500
	game.buy_item(actor, 10)
	game.buy_item(actor, Gear.TEAM_BOOTS)
	actor.stats.stuns = 9
	actor.ability_cooldown = 6
	game.skip_shop()
	game.score = [1, 1]
	game.time_left = 0.01
	game._physics_process(0.02)
	check(game.overtime_count == 1 and game.time_left == 120 and not game.shop_open and not game.finished, "regulation tie starts full overtime with kickoff only")
	check(actor.stats.stuns == 9 and actor.inventory == [10] and actor.gold == 2500 - Gear.ITEMS[10].cost - Gear.ITEMS[Gear.TEAM_BOOTS].cost and actor.ability_cooldown == 6 and game.team_upgrades[0][0] == 1, "overtime preserves growth, equipment, gold, cooldown and team upgrades")
	check(game.match_elapsed() == 300 and game.kickoff_team == 1, "first overtime clock is continuous and kickoff alternates")
	game._physics_process(game.goal_pause + 0.01)
	game.time_left = 110
	game.last_touch = actor
	game.ball.position = Vector3(48.5, 0.34, 0)
	game._check_boundaries()
	check(game.goal_events.back().time == 310 and not game.finished, "overtime goal has continuous timestamp and does not cause sudden death")
	game.score = [2, 2]
	game._physics_process(game.goal_pause + 0.01)
	game.time_left = 0.01
	game._physics_process(0.02)
	check(game.overtime_count == 2 and game.time_left == 120 and game.match_elapsed() == 420 and game.kickoff_team == 0, "a second tie adds another two minutes with alternating kickoff")
	game._physics_process(game.goal_pause + 0.01)
	game.score = [3, 2]
	game.time_left = 0.01
	game._physics_process(0.02)
	check(game.finished and not game.shop_open and game.overtime_count == 2, "a non-tied overtime period ends the match")
	game.start_match()
	check(game.overtime_count == 0 and game.time_left == 300 and game.team_upgrades == [[0, 0], [0, 0]] and actor.stats.stuns == 0, "new match clears overtime and match progression")
	game.skip_shop()
	game.score = [1, 0]
	game.time_left = 0.01
	game._physics_process(0.02)
	check(game.finished and game.overtime_count == 0, "regulation winner finishes without extra time")
	print("RESULT: %d checks, %d failures" % [checks, failures])
	game.free()
	quit(1 if failures else 0)


func check_pressure() -> void:
	game.skip_shop()
	for p in game.players:
		p.reset_position(true)
		p.position = Vector3(10, 0, 25)
		p.target = p.position
		p.ai_think_wait = 10
		p.tactical_line = F.Line.KEEPER if p.goalkeeper else F.Line.MID
	var defenders: Array = [game.players[1], game.players[2], game.players[3]]
	var attacker = game.players[20]
	var receiver = game.players[19]
	attacker.tactical_line = F.Line.FRONT
	receiver.tactical_line = F.Line.FRONT
	game.carrier = attacker
	var previous_gap := 0.0
	for near_goal in [false, true]:
		var x := -35.0 if near_goal else -15.0
		attacker.position = Vector3(x, 0, 0)
		receiver.position = Vector3(x - 1, 0, 9)
		game.ball.position = attacker.position
		for i in range(3):
			defenders[i].tactical_line = F.Line.BACK
			defenders[i].position = Vector3(x + 5, 0, -2 + i * 4)
		var plan: Dictionary = game._defensive_targets(0, attacker.position)
		var close_count := plan.values().filter(func(p): return p.distance_to(attacker.position) < 3).size()
		check(close_count == 1, "one presses while the second defender covers instead of crowding the ball")
		check(plan[defenders[2]].distance_to(receiver.position) < 3, "remaining defender marks a distinct dangerous forward")
		var gap: float = plan[defenders[0]].distance_to(attacker.position)
		if near_goal:
			check(gap < previous_gap, "pressure closes the gap as the attacker approaches the goal")
		previous_gap = gap
	check(is_equal_approx(game.goal_threat(0, Vector3(-35, 0, 4)), game.goal_threat(1, Vector3(35, 0, -4))), "goal threat is mirrored fairly for both teams")
	var defender = defenders[0]
	var old_target: Vector3 = defender.target
	defender.ai_think_wait = 0.15
	game._update_ai(0.05)
	check(defender.target == old_target, "defensive pressure still waits for the NPC observation interval")
	game._update_ai(0.2)
	check(defender.target.distance_to(attacker.position) < 3, "defender commits to pressure on its next observation")
	defender.human = true
	check(not game._defensive_targets(0, attacker.position).has(defender), "pressure AI never redirects the human player")
	defender.human = false
