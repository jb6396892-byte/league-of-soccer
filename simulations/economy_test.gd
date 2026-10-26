extends SceneTree

const Gear = preload("res://scripts/equipment.gd")
const Roles = preload("res://scripts/archetypes.gd")
var checks := 0
var failures := 0


func _initialize() -> void:
	call_deferred("run")


func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
	print(("PASS: " if ok else "FAIL: ") + message)


func loadout(game: Node, actor: Node3D, kind: int, items: Array) -> void:
	actor.archetype = kind
	actor.reset_position(true)
	actor.position = Vector3.ZERO
	actor.target = Vector3(30, 0, 0)
	actor.gold = 10000
	game.open_shop(0, "TEST")
	for item_id in items:
		check(game.buy_item(actor, item_id), "purchase item %d" % item_id)


func run() -> void:
	var game = load("res://main.tscn").instantiate()
	game.simulation_mode = true
	root.add_child(game)
	game.set_physics_process(false)
	game.player.human = true
	game.start_match()
	var actor = game.player
	var enemy = game.players[20]
	check(game.shop_open and game.goal_pause == 15 and actor.gold == 500, "match begins with 500 gold and 15s shop")
	check(game.buy_item(actor, 0) and actor.gold == Gear.START_GOLD - Gear.ITEMS[0].cost, "purchase deducts exact price")
	check(not game.buy_item(actor, 7) and not game.buy_item(actor, 17) and actor.gold == Gear.START_GOLD - Gear.ITEMS[0].cost and actor.inventory.size() == 1, "unaffordable completed-item purchases are atomic")
	check(not game.buy_item(actor, -1) and not game.buy_item(actor, Gear.ITEMS.size()), "invalid item ids cannot transact")
	actor.gold = 5000
	check(not game.buy_item(actor, 9), "role-specific gear rejects wrong class")
	for item_id in [2, 3, 5, 1, 6]:
		game.buy_item(actor, item_id)
	check(actor.inventory.size() == 6 and not game.buy_item(actor, 4), "inventory has six slots")
	var before: int = actor.gold
	check(game.sell_item(actor, 0) and actor.gold == before + Gear.sell_price(0) and not 0 in actor.inventory, "sell refunds 70 percent and removes item")
	var clock: float = game.time_left
	var gold: int = actor.gold
	actor.ability_cooldown = 7.0
	game.paused = true
	game._physics_process(2.0)
	check(game.goal_pause == 15 and not game.buy_item(actor, 0) and not game.sell_item(actor, 0), "pause freezes shopping and disallows hidden purchases")
	game.paused = false
	game._physics_process(1.1)
	check(game.players.all(func(p): return p.human or (not p.inventory.is_empty() and p.gold >= 0)), "NPCs buy affordable class starters")
	check(game.time_left == clock and actor.gold == gold and actor.ability_cooldown == 7.0, "shop time gives no match income or cooldown progress")
	game._physics_process(14.0)
	check(not game.shop_open and game.is_playing() and actor.inventory.size() == 5 and actor.gold == gold, "shop closes and kickoff preserves wallet and gear")
	check(not game.buy_item(actor, 0) and not game.sell_item(actor, 0), "active play cannot buy or sell")
	# Income accumulates only during active time; possession fragments count.
	actor.gold = 500
	actor.possession_income = 0
	game.stipend_clock = 0
	game.carrier = actor
	game._update_economy(3.0)
	game.carrier = enemy
	game._update_economy(2.0)
	game.carrier = actor
	game._update_economy(2.0)
	check(actor.gold == 520 and is_zero_approx(actor.possession_income), "five accumulated held seconds award exactly 20 gold")
	game.carrier = null
	game._update_economy(Gear.STIPEND_SECONDS - 7.0)
	check(actor.gold == 520 + Gear.STIPEND_GOLD and is_zero_approx(game.stipend_clock), "all players receive the stipend only at its active-time boundary")
	for other in game.players:
		other.position = Vector3(-35, 0, 22)
	actor.position = Vector3.ZERO
	enemy.position = Vector3(1.1, 0, 0)
	game.carrier = enemy
	game.possession_lock = 0
	actor.defense_reward_wait = 0
	game._update_possession(1.0 / 60)
	check(actor.gold == 570 + Gear.STIPEND_GOLD and game.carrier == actor, "real tackle awards 50 gold")
	game.carrier = enemy
	game.possession_lock = 0
	game._update_possession(1.0 / 60)
	check(actor.gold == 570 + Gear.STIPEND_GOLD, "rapid repeated steals do not farm money")
	game.carrier = null
	game._update_economy(6.1)
	enemy.position = Vector3(15, 0, 0)
	game.last_touch = enemy
	game.ball.position = Vector3(0.4, 0.34, 0)
	game.ball.velocity = Vector3.ZERO
	game.possession_lock = 0
	game._update_possession(1.0 / 60)
	check(actor.gold == 595 + Gear.STIPEND_GOLD and game.carrier == actor, "intercept after reward cooldown awards 25 gold")
	gold = actor.gold
	var enemy_gold: int = enemy.gold
	game.last_touch = actor
	game.ball.position = Vector3(48.5, 0.34, 0)
	game._check_boundaries()
	check(actor.gold == gold + 360 and enemy.gold == enemy_gold and not game.shop_open and game.goal_pause == 1.8, "goal rewards remain intact and restart no longer opens a shop")
	game.reset_kickoff(0)
	gold = actor.gold
	game.last_touch = actor
	game.ball.position = Vector3(-48.5, 0.34, 0)
	game._check_boundaries()
	check(actor.gold == gold and actor.stats.own_goals == 1, "own goal gives no personal or own-team reward")
	# Observe gear in ball physics, possession, fields and movement skills.
	loadout(game, actor, 0, [0, 1, 2, 3])
	actor.step(1.0, [])
	check(is_equal_approx(actor.position.x, 7.8 * 1.05 * 1.08), "boots increase actual movement distance")
	check(is_equal_approx(actor.collision_radius(), 0.51 * 1.12), "greaves enlarge actual collision radius")
	game.kick_ball(actor, Vector3.RIGHT, 29.0)
	check(is_equal_approx(game.ball.velocity.x, 29.0 * 1.15), "power gear increases actual ball velocity")
	game.use_ability(actor)
	check(is_equal_approx(actor.ability_cooldown, 9.6), "watch reduces next W cooldown")
	loadout(game, actor, 0, [4, 5, 7])
	enemy.position = Vector3(15, 0, 0)
	game.carrier = null
	game.possession_lock = 0
	game.last_touch = enemy
	game.ball.position = Vector3(1.32, 0.34, 0)
	game.ball.velocity = Vector3.ZERO
	game._update_possession(1.0 / 60)
	check(game.carrier == actor and is_equal_approx(game.possession_lock, 0.8), "socks collect beyond normal reach and charm extends possession protection")
	game.use_ability(actor)
	check(actor.ability_time == 2.25 and is_equal_approx(actor.move_speed(), 7.8 * 1.05 * 1.08 * (Roles.SPRINT_MULTIPLIER + 0.1)), "runner upgrade grants 2.25-second sprint with its additive multiplier")
	loadout(game, actor, 1, [8])
	enemy.inventory.clear()
	enemy.inventory.append(6)
	enemy.position = Vector3(5.5, 0, 0)
	game.use_ability(actor)
	game._apply_slow_fields()
	check(actor.ability_time == 6 and is_equal_approx(enemy.slow_multiplier, 0.82), "extended guard field reaches 5.5m and resistance reduces slow to 18 percent")
	loadout(game, actor, 2, [9, 3])
	game.use_ability(actor)
	actor.step(0.51, [])
	game.carrier = actor
	game.release_ability(actor)
	check(is_equal_approx(actor.dash_remaining, 11) and is_equal_approx(actor.ability_cooldown, 3.2), "charger reaches full 11m dash in 0.51s with reduced cooldown")
	game.start_match()
	check(game.players.all(func(p): return p.gold == 500 and p.inventory.is_empty() and p.stats.gold_earned == 0), "new match resets everyone's gear and economy")
	actor.gold = 30000
	for i in range(Gear.TEAM_UPGRADE_CAP):
		check(game.buy_item(actor, Gear.TEAM_BOOTS), "team speed upgrade allowed up to shared cap")
	var teammate = game.players.filter(func(p): return p.team == actor.team and p != actor)[0]
	teammate.gold = 1000
	check(not game.buy_item(teammate, Gear.TEAM_BOOTS) and teammate.gold == 1000, "teammate cannot exceed shared cap or lose gold on rejection")
	check(game.buy_item(teammate, Gear.TEAM_SCYTHE), "weakening has an independent shared cap")
	enemy.gold = 1000
	check(game.buy_item(enemy, Gear.TEAM_BOOTS), "opposing team retains independent upgrades")
	check(game.team_upgrades[actor.team][0] == Gear.TEAM_UPGRADE_CAP and game.purchase_error(actor, Gear.TEAM_BOOTS).contains("上限"), "shop exposes upgrade limit")
	game.start_match()
	check(game.team_upgrades == [[0, 0], [0, 0]], "new match resets shared upgrade caps")
	print("RESULT: %d checks, %d failures" % [checks, failures])
	game.free()
	quit(1 if failures else 0)
