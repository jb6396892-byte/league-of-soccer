extends RefCounted
## Real inputs and match events drive lessons; there is no timer or AI match here.
const LESSONS := [
	["移动到光圈", "右键点击球场，走进青柠色目标圈。"],
	["带球推进", "球已传给你。右键移动到下一个光圈，保持控球。"],
	["把球送进球门", "左键朝右侧球门调整方向，再按 Q 射门。进球后继续。"],
	["使用英雄技能", "按 W 疾跑，再右键跑进光圈；体验至少 2 秒后继续。"],
	["购买并使用 E", "购买急行或追风，Enter 返回；按 E 跑进光圈，体验至少 2 秒。"]
]
const SKILL_PRACTICE_SECONDS := 2.0
var game: Node3D
var step := 0
var elapsed := 0.0
var waypoint := Vector3.ZERO
var baseline := 0
var skill_elapsed := 0.0


func _init(match_node: Node3D) -> void:
	game = match_node


func start() -> void:
	# A single stationary opponent makes control effects observable in the lab.
	for actor in game.players.duplicate():
		if actor == game.player:
			continue
		if game.mode == "training" and actor.team == 1 and actor.shirt_number == 10:
			actor.set_archetype(1)
			continue
		game.players.erase(actor)
		actor.free()
	for actor in game.players:
		actor.reset_position(true)
	game.player.gold = 100000
	game.shop_open = false
	game.goal_pause = 0.0
	game.supply_shop = false
	elapsed = 0.0
	step = 0
	reset_field()
	if game.mode == "tutorial":
		begin_lesson()
	else:
		refill()


func reset_field() -> void:
	game._clear_projectiles()
	var actor = game.player
	actor.cancel_charge()
	actor.dash_remaining = 0.0
	actor.stun_time = 0.0
	actor.throw_windup = 0.0
	actor.position = Vector3(-44, 0, 0) if actor.goalkeeper else Vector3(23, 0, 0)
	actor.facing = Vector3.RIGHT
	actor.target = actor.position
	actor.velocity = Vector3.ZERO
	for other in game.players:
		if other != actor:
			other.position = Vector3(-30, 0, 7) if actor.goalkeeper else Vector3(31, 0, 7)
			other.target = other.position
			other.velocity = Vector3.ZERO
			other.stun_time = 0.0
	give_ball()
	if not game.simulation_mode:
		game._update_camera(1.0)


func give_ball() -> void:
	game.carrier = game.player
	game.last_touch = game.player
	game.possession_lock = 1.0
	game.ball.position = game.player.position + game.player.facing * game.player.control_distance() + Vector3.UP * game.Ball.RADIUS
	game.ball.velocity = Vector3.ZERO
	game.ball.trail_points.clear()
	game.ball.update_visual(0.0)


func refill() -> void:
	var actor = game.player
	actor.gold = 100000
	actor.ability_cooldown = 0.0
	actor.kick_cooldown = 0.0
	actor.e_cooldown = 0.0
	for id in game.ESkills.visible_skills(actor.archetype):
		actor.e_charges[id] = 99
	actor.e_selected = actor.archetype + 3
	game.announce("技能已刷新 · E 次数与试装金币已补满", 2.0)


func serve_shot() -> void:
	# Keeper training: an incoming ground shot that can be caught with Q.
	game.carrier = null
	game.last_touch = game.players[1]
	game.ball.position = game.player.position + Vector3(12, 0.34, 0)
	game.ball.velocity = Vector3(-23, 0, 0)
	game.possession_lock = 0.2


func begin_lesson() -> void:
	var actor = game.player
	skill_elapsed = 0.0
	match step:
		0:
			actor.position = Vector3(10, 0, 0)
			actor.target = actor.position
			game.carrier = null
			game.ball.position = Vector3(2, 0.34, 0)
			waypoint = Vector3(17, 0, 6)
		1:
			give_ball()
			waypoint = Vector3(25, 0, 0)
		2:
			reset_field()
			baseline = game.score[0]
		3:
			reset_field()
			waypoint = Vector3(41, 0, 0)
			actor.ability_cooldown = 0.0
			baseline = actor.stats.casts
		4:
			reset_field()
			waypoint = Vector3(41, 0, 0)
			actor.e_charges.clear()
			actor.e_selected = -1
			actor.e_cooldown = 0.0
			baseline = actor.stats.e_casts
			game.open_shop(0, "教学补给 · 购买 E 使用次数", true)
			if not game.simulation_mode:
				game.hud.shop_tab = 2


func update(delta: float) -> void:
	elapsed += delta
	if game.mode != "tutorial":
		return
	var passed := false
	match step:
		0: passed = game.player.position.distance_to(waypoint) < 1.8
		1: passed = game.carrier == game.player and game.player.position.distance_to(waypoint) < 1.8
		2: passed = game.score[0] > baseline
		3, 4:
			var cast: bool = game.player.stats.casts > baseline if step == 3 else game.player.stats.e_casts > baseline and not game.e_purchase_events.is_empty()
			if cast:
				skill_elapsed += delta
			passed = cast and skill_elapsed >= SKILL_PRACTICE_SECONDS and game.player.position.distance_to(waypoint) < 1.8
	if passed:
		step += 1
		if step == LESSONS.size():
			game.finish_session(true)
		else:
			begin_lesson()
