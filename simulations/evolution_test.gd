extends SceneTree
const Roles = preload("res://scripts/archetypes.gd")
const Gear = preload("res://scripts/equipment.gd")
var game: Node
var checks := 0
var failures := 0


func _initialize() -> void:
	call_deferred("run")


func check(ok: bool, text: String) -> void:
	checks += 1
	if not ok:
		failures += 1
	print(("PASS: " if ok else "FAIL: ") + text)


func hit(actor: Node3D, enemy: Node3D) -> float:
	actor.ability_cooldown = 0
	actor.throw_windup = 0
	actor.position = Vector3.ZERO
	actor.target = actor.position
	enemy.position = Vector3(6, 0, 0)
	enemy.stun_time = 0
	game.use_ability(actor, Vector3.RIGHT)
	game._update_projectiles(0.51)
	actor.step(0.51, [])
	game._update_projectiles(0.4)
	return enemy.stun_time


func run() -> void:
	game = load("res://main.tscn").instantiate()
	game.simulation_mode = true
	root.add_child(game)
	game.set_physics_process(false)
	game.rng.seed = 20261020
	game.start_match()
	game.skip_shop()
	var actor = game.player
	var enemy = game.players[20]
	for other in game.players:
		other.reset_position(true)
		other.position = Vector3(30, 0, 25)
	actor.archetype = Roles.Kind.STRIKER
	actor.human = true
	check(is_equal_approx(actor.move_speed(), 7.8 * 0.95), "flag keeps minus-five-percent base speed")
	actor.stats.goals = 3
	check(is_equal_approx(actor.move_speed(), 7.8 * 0.95), "goals cannot grant the removed movement bonus")
	check(actor.mobile_throw(), "mobile casting available before first hit")
	var first_stun := hit(actor, enemy)
	check(first_stun == 1.0 and actor.stats.stuns == 1, "first hit grants exactly one hit statistic")
	check(is_equal_approx(actor.throw_radius(), Roles.THROW_RADIUS), "hit does not grow projectile width")
	check(is_equal_approx(actor.throw_speed(), 20.0), "base projectile speed reduced to twenty and never grows")
	for i in range(3):
		hit(actor, enemy)
	check(hit(actor, enemy) == 1.0 and actor.stats.stuns == 5, "fifth hit completes milestone without retroactive stun change")
	check(actor.throw_stun() == 1.0, "five hits no longer upgrade stun")
	check(hit(actor, enemy) == 1.0, "sixth shot still applies one second stun")
	for i in range(4):
		hit(actor, enemy)
	check(actor.stats.stuns == 10 and actor.mobile_throw() and actor.evolution_times == [-1.0, -1.0], "hit count cannot trigger evolution")
	actor.ability_cooldown = 0
	actor.position = Vector3.ZERO
	actor.target = Vector3(10, 0, 0)
	game.use_ability(actor, Vector3.FORWARD)
	var shot = game.projectiles[0]
	check(shot.mobile_cast and is_equal_approx(shot.radius, actor.throw_radius()), "cast snapshots current equipment and collision size")
	actor.step(0.2, [])
	game._update_projectiles(0.2)
	check(actor.position.x > 0 and shot.position.is_equal_approx(actor.position) and shot.windup > 0, "mobile windup moves and warning follows caster")
	check(shot.direction == Vector3.FORWARD, "movement never silently changes warned throw direction")
	game._update_projectiles(0.31)
	var launched_at: Vector3 = shot.position
	actor.step(0.1, [])
	game._update_projectiles(0.1)
	check(shot.position.is_equal_approx(launched_at + Vector3.FORWARD * shot.speed * 0.1), "launched shot travels independently at its fixed speed")
	game.reset_kickoff(1)
	check(actor.stats.stuns == 10 and actor.mobile_throw(), "kickoff retains hit statistics and initial mobile casting")
	game.open_shop(0, "test")
	actor.gold = 10000
	check(game.buy_item(actor, 10), "flag can buy its exclusive item")
	check(is_equal_approx(actor.throw_range(), Roles.THROW_RANGE + 4.0) and is_equal_approx(actor.throw_speed(), Roles.THROW_SPEED * 1.2), "flag exclusive extends range and boosts fixed base speed")
	check(not game.buy_item(actor, 11), "other role exclusive remains unpurchasable")
	for kind in range(6):
		var visible := Gear.visible_items(kind)
		check(visible.size() == 17 and visible.filter(func(id): return Gear.ITEMS[id].role >= 0) == [14 if kind == 5 else 7 + kind], "role %d shop exposes exactly its own exclusive" % kind)
	var keeper = game.players[0]
	keeper.gold = 10000
	check(game.buy_item(keeper, 11), "keeper can buy its exclusive item")
	check(is_equal_approx(keeper.save_window(), Roles.SAVE_WINDOW + 0.45) and is_equal_approx(keeper.keeper_radius(), Roles.KEEPER_SLOW_RADIUS + 2), "keeper exclusive improves save window and cone")
	for id in [0, 2, 3, 4, 5]:
		game.buy_item(actor, id)
	check(actor.inventory.size() == 6, "ordinary loadout is full")
	var own_before: float = actor.move_speed()
	var enemy_before: float = enemy.move_speed()
	var gold_before: int = actor.gold
	check(game.buy_item(actor, Gear.TEAM_BOOTS) and game.buy_item(actor, Gear.TEAM_BOOTS), "full inventory can buy the same team upgrade repeatedly")
	check(actor.inventory.size() == 6 and actor.gold == gold_before - 2 * Gear.ITEMS[Gear.TEAM_BOOTS].cost, "repeat upgrades deduct full catalog price each and occupy no slots")
	check(is_equal_approx(actor.move_speed(), own_before * 1.015 * 1.015) and is_equal_approx(enemy.move_speed(), enemy_before), "evolution boots buff own team only multiplicatively")
	check(game.buy_item(actor, Gear.TEAM_SCYTHE) and is_equal_approx(enemy.move_speed(), enemy_before * 0.985), "weakness scythe affects opposing team only")
	enemy.gold = 1600
	game.buy_item(enemy, Gear.TEAM_BOOTS)
	game.buy_item(enemy, Gear.TEAM_SCYTHE)
	check(is_equal_approx(actor.move_speed(), own_before * pow(1.015, 2) * 0.985), "opposing team purchases combine with existing speed upgrades")
	check(game.team_upgrades == [[2, 1], [1, 1]] and actor.team_purchases == [2, 1], "team and individual purchase counters record repeated transactions")
	var before_upgrade: float = game.team_speed(0)
	game.sell_item(actor, 0)
	check(game.team_speed(0) == before_upgrade, "selling ordinary equipment cannot refund or remove team upgrades")
	game.reset_kickoff(1)
	check(game.team_speed(0) == before_upgrade and actor.team_speed_multiplier == before_upgrade, "team upgrades persist through kickoff")
	game.open_shop(0, "test")
	actor.gold = Gear.ITEMS[Gear.TEAM_SCYTHE].cost - 1
	check(not game.buy_item(actor, Gear.TEAM_SCYTHE) and actor.gold == Gear.ITEMS[Gear.TEAM_SCYTHE].cost - 1, "insufficient funds never apply team upgrade")
	game.paused = true
	actor.gold = 800
	check(not game.buy_item(actor, Gear.TEAM_BOOTS), "paused shop cannot buy upgrades")
	game.paused = false
	game.skip_shop()
	check(not game.buy_item(actor, Gear.TEAM_BOOTS), "active match cannot purchase team upgrades")
	game.start_match()
	check(game.team_upgrades == [[0, 0], [0, 0]] and game.players.all(func(a): return a.team_speed_multiplier == 1 and a.stats.stuns == 0 and a.team_purchases == [0, 0]), "new match clears evolution and all team effects")
	# Every NPC route completes six completed items before any team upgrade.
	var investor = game.players[5]
	investor.archetype = Roles.Kind.RUNNER
	investor.build_variant = 2
	investor.gold = preload("res://scripts/purchasable_skills.gd").SKILLS[2].cost + Gear.ITEMS[Gear.TEAM_BOOTS].cost - 1
	for id in Gear.NPC_BUILDS[0][2]:
		investor.gold += Gear.ITEMS[id].cost
	game._npc_shop()
	check(investor.inventory.size() == 6 and investor.team_purchases == [0, 0] and investor.gold == Gear.ITEMS[Gear.TEAM_BOOTS].cost - 1, "NPC completes six completed items before saving for team upgrades")
	investor.gold += 1
	game._npc_shop()
	check(investor.inventory.size() == 6 and investor.team_purchases[0] + investor.team_purchases[1] == 1 and investor.gold == 0, "NPC pays full catalog price for team upgrade after completing its build")
	print("RESULT: %d checks, %d failures" % [checks, failures])
	game.free()
	quit(1 if failures else 0)
