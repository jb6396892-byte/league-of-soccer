extends SceneTree
const Gear = preload("res://scripts/equipment.gd")
const Roles = preload("res://scripts/archetypes.gd")
const ES = preload("res://scripts/purchasable_skills.gd")
var checks := 0
var failures := 0
var game: Node3D
var actor: Node3D
var enemy: Node3D


func _initialize() -> void:
	call_deferred("run")


func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
	print(("PASS: " if ok else "FAIL: ") + message)


func setup(kind: int) -> void:
	game._clear_projectiles()
	for p in game.players:
		p.reset_position(true)
		p.human = true
		p.position = Vector3(40, 0, 25)
	actor.archetype = kind
	actor.position = Vector3.ZERO
	actor.target = Vector3(20, 0, 0)
	actor.gold = 10000
	enemy.position = Vector3(8, 0, 0)
	game.carrier = null
	game.paused = false
	game.open_shop(0, "TEST")


func play() -> void:
	game.shop_open = false
	game.goal_pause = 0.0


func run() -> void:
	game = load("res://main.tscn").instantiate()
	game.simulation_mode = true
	root.add_child(game)
	game.set_physics_process(false)
	game.start_match()
	actor = game.player
	enemy = game.players[20]
	setup(0)
	actor.gold = Gear.ITEMS[15].cost
	check(game.buy_item(actor, 0) and game.buy_item(actor, 4), "buy two component types")
	check(actor.gold == Gear.ITEMS[15].cost - Gear.ITEMS[0].cost - Gear.ITEMS[4].cost and Gear.buy_cost(actor.inventory, 15) == actor.gold, "full component value credited once")
	check(game.buy_item(actor, 15) and actor.gold == 0 and actor.inventory == [15], "combine consumes components and exact balance")
	check(is_equal_approx(actor.equipment_bonus("speed"), 0.12) and is_equal_approx(actor.equipment_bonus("pickup"), 0.2), "combined gear replaces rather than double-counts component stats")
	actor.gold = 10000
	check(not game.buy_item(actor, 15), "completed item unique")
	check(game.sell_item(actor, 0) and actor.gold == 10000 + Gear.sell_price(15), "completed item sells for 70 percent of full cost")
	for id in [5, 5, 1, 2, 3, 4]:
		game.buy_item(actor, id)
	check(actor.inventory.size() == 6 and actor.inventory.count(5) == 2, "six slots allow repeated components")
	var before: int = actor.gold
	check(not game.buy_item(actor, 5) and actor.gold == before, "full inventory rejects additional component atomically")
	check(Gear.buy_cost(actor.inventory, 17) == Gear.ITEMS[17].cost - Gear.ITEMS[5].cost - Gear.ITEMS[2].cost and game.buy_item(actor, 17), "full slots allow recipe consuming owned materials")
	check(actor.inventory.size() == 5 and actor.inventory.count(5) == 1 and actor.inventory.count(2) == 0 and actor.gold == before - Gear.ITEMS[17].cost + Gear.ITEMS[5].cost + Gear.ITEMS[2].cost, "only recipe quantity consumed; unrelated duplicate survives")
	actor.inventory.clear()
	actor.inventory.append(0)
	actor.gold = Gear.ITEMS[7].cost - Gear.ITEMS[0].cost - 1
	check(not game.buy_item(actor, 7) and actor.inventory == [0] and actor.gold == Gear.ITEMS[7].cost - Gear.ITEMS[0].cost - 1, "unaffordable partial recipe keeps all assets")
	actor.gold += 1
	check(game.buy_item(actor, 7) and actor.inventory == [7] and actor.gold == 0, "missing component bought inside upgrade without occupying a temporary slot")
	actor.inventory.assign([6, 16, 21])
	check(is_equal_approx(actor.slow_resistance(), 0.7), "multiple resistance items respect 70 percent cap")
	for kind in range(6):
		setup(kind)
		var exclusive := 14 if kind == 5 else 7 + kind
		check(game.buy_item(actor, exclusive) and Gear.visible_items(kind, 1).size() == 8, "role %d sees and buys its own completed gear" % kind)
		check(not game.buy_item(actor, 14 if kind != 5 else 7), "role %d cannot buy other hero gear" % kind)
	setup(5)
	for team in range(2):
		actor.team = team
		actor.position.x = -10 if team == 0 else 10
		check(is_equal_approx(actor.move_speed(), 7.8 * 1.1), "team %d warden home-half speed" % team)
		actor.position.x *= -1
		check(is_equal_approx(actor.move_speed(), 7.8 * 0.85), "team %d warden opposing-half speed" % team)
	actor.team = 0
	actor.position = Vector3(-10, 0, 0)
	play()
	check(game.use_ability(actor, Vector3.ZERO, Vector3(47, 0, 0)), "warden casts targeted W")
	check(game.fields.size() == 1 and game.fields[0].position == Vector3(20, 0, 0) and game.fields[0].radius == 10 and game.fields[0].remaining == 12 and actor.ability_cooldown == 60, "W clamps target to 30m and applies specified duration radius cooldown")
	enemy.position = Vector3(30, 0, 0)
	actor.position = Vector3(-35, 0, 0)
	actor.stun_time = 2
	game._apply_slow_fields()
	check(is_equal_approx(enemy.slow_multiplier, 0.7) and actor.slow_multiplier == 1, "fixed field survives caster movement and stun; enemies only")
	game.create_field(actor, Vector3(20, 0, 0), 10, 12, 0.7, "TEST")
	game._apply_slow_fields()
	check(is_equal_approx(enemy.slow_multiplier, 0.7), "overlapping domains do not stack")
	enemy.position = Vector3(33, 0, 0)
	game._apply_slow_fields()
	check(enemy.slow_multiplier == 1, "exiting field restores movement")
	game._update_fields(11.9)
	check(game.fields.size() == 2, "domain survives nearly twelve seconds")
	game._update_fields(0.2)
	game._apply_slow_fields()
	check(game.fields.is_empty() and enemy.slow_multiplier == 1, "domain expires and restores speed")
	setup(5)
	game.buy_item(actor, 14)
	play()
	game.use_ability(actor, Vector3.ZERO, Vector3(40, 0, 0))
	check(game.fields[0].radius == 11 and game.fields[0].position.x == 35 and actor.ability_cooldown == 48, "warden exclusive upgrades actual area range and cooldown")
	setup(3)
	enemy.inventory.assign([16])
	play()
	game.use_ability(actor, Vector3.RIGHT)
	game._update_projectiles(0.51)
	game._update_projectiles(0.4)
	check(is_equal_approx(enemy.stun_time, 0.8) and is_equal_approx(actor.stats.stun_seconds, 0.8) and actor.stats.stuns == 1, "unflinching greaves reduce actual stun and recorded duration while retaining hit statistics")
	actor.stats.stuns = 5
	actor.ability_cooldown = 0
	actor.throw_windup = 0
	enemy.stun_time = 0
	game.use_ability(actor, Vector3.RIGHT)
	game._update_projectiles(0.51)
	game._update_projectiles(0.4)
	check(is_equal_approx(enemy.stun_time, 0.8), "five hits do not evolve stun; greaves still reduce it to 0.8 seconds")
	setup(0)
	actor.gold = ES.SKILLS[0].cost + ES.SKILLS[1].cost
	check(game.buy_e(actor, 0) and game.buy_e(actor, 1) and actor.gold == 0 and actor.inventory.is_empty(), "E purchases exact charge price without equipment slot")
	check(actor.e_selected == 1 and actor.e_charges == {0: 1, 1: 1} and game.equip_e(actor, 0), "different E stocks persist and shop selection switches")
	actor.gold = 10000
	check(not game.buy_e(actor, 8) and not game.buy_e(actor, -1), "E enforces hero and valid identifier boundaries")
	game.paused = true
	check(not game.buy_e(actor, 0) and not game.equip_e(actor, 1), "paused shop disallows E transactions and switches")
	game.paused = false
	play()
	check(not game.equip_e(actor, 1) and not game.buy_e(actor, 0), "active match disallows E trading and switching")
	check(game.use_e(actor) and actor.e_charges[0] == 0 and actor.e_cooldown == 12, "successful E consumes exactly one charge")
	check(not game.use_e(actor) and actor.e_charges[0] == 0, "empty or cooling E cannot be reused")
	check(is_equal_approx(actor.move_speed(), 7.8 * 1.05 * 1.2), "general haste changes real movement")
	game.open_shop(0, "test")
	game.equip_e(actor, 1)
	check(actor.e_cooldown == 12, "switching E does not reset shared cooldown")
	game.reset_kickoff(0)
	check(actor.e_selected == 1 and actor.e_charges[1] == 1 and actor.e_cooldown == 12 and actor.e_boost_time == 0, "kickoff preserves charges and cooldown, clears temporary buffs")
	actor.e_cooldown = 0
	actor.stun_time = 2
	actor.slow_multiplier = 0.7
	check(game.use_e(actor) and actor.stun_time == 0 and actor.e_immunity_time == 2, "cleanse can release during stun and removes control")
	game.create_field(enemy, actor.position, 12, 4, 0.6, "test")
	game._apply_slow_fields()
	check(actor.slow_multiplier == 1, "immunity ignores fixed slow fields")
	actor.step(2.01, [])
	game._apply_slow_fields()
	check(is_equal_approx(actor.slow_multiplier, 0.6), "slow applies again after immunity expires")
	for kind in range(6):
		setup(kind)
		var id := kind + 3
		game.buy_e(actor, id)
		play()
		var ally = game.players[2]
		ally.position = Vector3(2, 0, 0)
		ally.stun_time = 1
		game.carrier = actor
		check(game.use_e(actor, Vector3(10, 0, 0)) and actor.e_charges[id] == 0 and actor.stats.e_casts == 1, "role %d exclusive E consumes one charge" % kind)
		match kind:
			0: check(actor.e_boost_multiplier == 1.25 and actor.e_boost_time == 3, "runner exclusive sprint")
			1:
				enemy.position = Vector3(5, 0, 0)
				game._apply_slow_fields()
				check(game.fields.size() == 1 and is_equal_approx(enemy.slow_multiplier, 0.6), "guard exclusive fixed 40 percent slow")
			2: check(actor.position == Vector3(5, 0, 0) and game.ball.position.distance_to(actor.position) < 2, "charger blink travels 5m with ball")
			3: check(ally.e_boost_multiplier == 1.18 and ally.e_boost_time == 4 and enemy.e_boost_time == 0, "flag boost reaches allies only")
			4: check(actor.save_time == 2 and actor.e_immunity_time == 2, "keeper E enables actual save window")
			5: check(ally.stun_time == 0 and ally.e_immunity_time == 2.5 and enemy.e_immunity_time == 0, "warden cleanses nearby allies only")
	setup(0)
	game.buy_e(actor, 2)
	play()
	check(not game.use_e(actor) and actor.e_charges[2] == 1, "failed situational E preserves charge")
	game.carrier = actor
	game.possession_lock = 0
	check(game.use_e(actor) and game.possession_lock == 1.3, "control E protects current possession")
	setup(2)
	game.buy_e(actor, 5)
	play()
	check(not game.use_e(actor) and not game.use_e(actor, actor.position) and actor.e_charges[5] == 1, "invalid blink target preserves charge")
	actor.position = Vector3(47, 0, 29)
	game.use_e(actor, Vector3(100, 0, 100))
	check(actor.position.is_equal_approx(actor.constrain_position(actor.position)) and actor.position.distance_to(Vector3(47, 0, 29)) <= 5.0, "blink respects field boundaries")
	setup(0)
	game.buy_e(actor, 1)
	play()
	actor.ability_time = 2.0
	game.grant_boost(actor, 1.25, 4.0)
	check(is_equal_approx(actor.move_speed(), 7.8 * 1.05 * Roles.SPRINT_MULTIPLIER), "W and E speed boosts take the strongest value without multiplying")
	actor.step(2.1, [])
	check(is_equal_approx(actor.move_speed(), 7.8 * 1.05 * 1.25), "longer E boost remains after W expires")
	actor.human = false
	actor.stun_time = 2
	actor.ai_think_wait = 0.2
	for i in range(15):
		game._update_ai(1.0 / 60)
	check(actor.stats.e_casts == 0 and actor.ai_e_wait > 0, "stunned NPC queues cleanse after observation and reaction")
	for i in range(40):
		game._update_ai(1.0 / 60)
	check(actor.stats.e_casts == 1 and actor.stun_time == 0, "NPC executes delayed cleanse while stunned")
	game.start_match()
	check(game.e_purchase_events.is_empty() and game.e_cast_events.is_empty() and game.fields.is_empty() and game.players.all(func(p): return p.e_charges.is_empty() and p.e_selected == -1 and p.e_cooldown == 0), "fresh match clears all E and area state")
	print("RESULT: %d checks, %d failures" % [checks, failures])
	game.free()
	quit(1 if failures else 0)
