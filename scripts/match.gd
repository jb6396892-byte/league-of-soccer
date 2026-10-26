extends Node3D

const Footballer = preload("res://scripts/footballer.gd")
const Ball = preload("res://scripts/ball.gd")
const Stadium = preload("res://scripts/stadium.gd")
const HUD = preload("res://scripts/hud.gd")
const S = preload("res://scripts/shapes.gd")
const Roles = preload("res://scripts/archetypes.gd")
const Gear = preload("res://scripts/equipment.gd")
const SkillProjectile = preload("res://scripts/skill_projectile.gd")
const Formations = preload("res://scripts/formations.gd")
const ESkills = preload("res://scripts/purchasable_skills.gd")
const AreaField = preload("res://scripts/area_field.gd")
const Settings = preload("res://scripts/match_settings.gd")
const Modes = preload("res://scripts/game_modes.gd")
const Practice = preload("res://scripts/practice.gd")
const NPCTactics = preload("res://scripts/npc_tactics.gd")
var net: Node
var tactics: RefCounted
signal session_finished(won: bool)
signal goal_scored(team: int)
signal ui_interaction(kind: String)
var mode := "free"
var challenge_id := 0
var practice: RefCounted
var rogue: RefCounted
var rogue_extra_time := 0.0
var result_won := false
const KICK_COOLDOWN := 0.42
const MATCH_DURATION := 300.0
const OVERTIME_DURATION := 120.0
const AI_THINK_INTERVAL := Vector2(0.25, 0.45)
const AI_SKILL_REACTION := Vector2(0.25, 0.55)
const AI_TACKLE_REACTION := Vector2(0.30, 0.60)
const AI_TURN_ERROR := 6.0
const AI_SHOT_ERROR := 10.0
const AI_PASS_ERROR := 6.0

var players: Array = []
var player: Node3D
var ball: Node3D
var carrier: Node3D
var possession_lock := 0.0
var camera: Camera3D
var hud: Control
var marker: Node3D
var tutorial_marker: Node3D
var marker_time := 0.0
var camera_focus := Vector3.ZERO
var camera_locked := true
var overview := false
var zoom_size := 36.0
var started := false
var paused := false
var finished := false
var help_visible := false
var time_left := MATCH_DURATION
var match_minutes := 5
var difficulty := Settings.Difficulty.NORMAL
var ally_difficulty := Settings.Difficulty.NORMAL
var regulation_duration := MATCH_DURATION
var score := [0, 0]
var goal_pause := 0.0
var kickoff_team := 0
var announcement := ""
var announcement_time := 0.0
var kick_sound: AudioStreamPlayer
var whistle_sound: AudioStreamPlayer
var rng := RandomNumberGenerator.new()
var simulation_mode := false
var agent_controlled := false
var selected_role := Roles.Kind.RUNNER
var ability_casts := [0, 0, 0, 0, 0, 0]
var projectiles: Array = []
var shots := 0
var last_touch: Node3D
var goal_events: Array = []
var loose_ball_seconds := 0.0
var shop_open := false
var shop_title := ""
var npc_shopped := false
var stipend_clock := 0.0
var supply_clock := 0.0
var supply_shop := false
var timeout_tokens := [1, 1]
var timeout_team := -1
var timeout_ai_wait := 3.0
var timeout_events: Array = []
var money_message := ""
var money_message_time := 0.0
var shop_feedback := ""
var team_upgrades := [[0, 0], [0, 0]]
var purchase_events: Array = []
var team_formations := [0, 0]
var overtime_count := 0
var fields: Array = []
var e_purchase_events: Array = []
var e_cast_events: Array = []


func _ready() -> void:
	rng.randomize()
	if not simulation_mode:
		_setup_world()
	_spawn_teams()
	ball = Ball.new()
	ball.visuals_enabled = not simulation_mode
	add_child(ball)
	tactics = NPCTactics.new(self)
	if simulation_mode:
		reset_kickoff(0)
		return
	marker = Node3D.new()
	add_child(marker)
	var marker_mat := S.material(Color("#dff78d"), true)
	S.ring(marker, Vector3.ZERO, 0.58, 0.075, marker_mat)
	S.rod(marker, Vector3(-0.25, 0, 0), Vector3(0.25, 0, 0), 0.04, marker_mat)
	S.rod(marker, Vector3(0, 0, -0.25), Vector3(0, 0, 0.25), 0.04, marker_mat)
	marker.visible = false
	if mode == "tutorial":
		tutorial_marker = Node3D.new()
		add_child(tutorial_marker)
		S.ring(tutorial_marker, Vector3.ZERO, 1.6, 0.09, marker_mat)
		S.rod(tutorial_marker, Vector3.ZERO, Vector3.UP * 1.8, 0.06, marker_mat)
		var target_label := Label3D.new()
		target_label.text = "练习目标"
		target_label.font_size = 36
		target_label.pixel_size = 0.015
		target_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		target_label.position.y = 2.1
		tutorial_marker.add_child(target_label)
		tutorial_marker.visible = false
	var canvas := CanvasLayer.new()
	add_child(canvas)
	hud = HUD.new()
	hud.game = self
	canvas.add_child(hud)
	_make_audio()
	reset_kickoff(0)


func _setup_world() -> void:
	add_child(Stadium.new())
	preload("res://scripts/match_presentation.gd").light_world(self)
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = zoom_size
	camera.far = 250
	add_child(camera)
	camera.current = true
	_update_camera(1.0)


func _spawn_teams() -> void:
	var formation := Formations.slots(0)
	for team in range(2):
		for slot in range(11):
			var actor := Footballer.new()
			actor.team = team
			actor.shirt_number = slot + 1
			var controlled := team == 0 and slot == 9
			actor.human = controlled and not simulation_mode
			actor.visuals_enabled = not simulation_mode
			actor.archetype = Roles.Kind.KEEPER if slot == 0 else (selected_role if controlled else Formations.random_hero(formation[slot].line, rng))
			actor.goalkeeper = slot == 0
			actor.home = formation[slot].home * (1.0 if team == 0 else -1.0)
			actor.tactical_line = formation[slot].line
			actor.name = ("Blue" if team == 0 else "Coral") + str(slot + 1)
			add_child(actor)
			players.append(actor)
			if controlled:
				player = actor


func assign_formation(team: int, fresh_roster: bool = false) -> void:
	if mode == "rogue":
		rogue.assign_team(self, team, fresh_roster)
		return
	if is_practice() and players.size() < 22:
		return
	var slots := Formations.slots(team_formations[team])
	var sign_x := 1.0 if team == 0 else -1.0
	var pool: Array = players.filter(func(a): return a.team == team and not a.goalkeeper)
	var keeper = players.filter(func(a): return a.team == team and a.goalkeeper)[0]
	keeper.home = slots[0].home * sign_x
	keeper.tactical_line = Formations.Line.KEEPER
	slots.remove_at(0)
	while pool.size() < slots.size():
		# Reduced squads remove midfield slots while preserving every hero's preferred line.
		var midfield: Array = slots.filter(func(s): return s.line == Formations.Line.MID)
		slots.erase(midfield.back())
	for actor in pool.duplicate():
		if actor.human:
			var preferred: Array = slots.filter(func(s): return s.line == Formations.PREFERRED_LINE[actor.archetype])
			preferred.sort_custom(func(a, b): return absf(a.home.z) < absf(b.home.z))
			var place: Dictionary = preferred[0] if not preferred.is_empty() else slots[0]
			actor.home = place.home * sign_x
			actor.tactical_line = place.line
			slots.erase(place)
			pool.erase(actor)
	if fresh_roster:
		for place in slots:
			var actor = pool.pop_at(rng.randi_range(0, pool.size() - 1))
			actor.set_archetype(Formations.random_hero(place.line, rng))
			actor.home = place.home * sign_x
			actor.tactical_line = place.line
		return
	# Assign natural positions first, then fill gaps with remaining heroes.
	var unfilled: Array = []
	for place in slots:
		var candidates: Array = pool.filter(func(a): return Formations.PREFERRED_LINE[a.archetype] == place.line)
		if candidates.is_empty():
			unfilled.append(place)
			continue
		candidates.sort_custom(func(a, b): return a.home.distance_squared_to(place.home * sign_x) < b.home.distance_squared_to(place.home * sign_x))
		var actor = candidates[0]
		actor.home = place.home * sign_x
		actor.tactical_line = place.line
		pool.erase(actor)
	for place in unfilled:
		pool.sort_custom(func(a, b): return absi(Formations.PREFERRED_LINE[a.archetype] - place.line) < absi(Formations.PREFERRED_LINE[b.archetype] - place.line))
		var actor = pool.pop_front()
		actor.home = place.home * sign_x
		actor.tactical_line = place.line


func choose_formation(index: int) -> bool:
	if is_practice() or mode == "rogue":
		return false
	if index < 0 or index >= Formations.NAMES.size() or paused or finished or (started and not shop_open):
		return false
	team_formations[0] = index
	assign_formation(0, not started)
	if not started:
		reset_kickoff(0)
	shop_feedback = "蓝队 %s · 下次开球采用新站位，角色和装备保留" % Formations.NAMES[index]
	return true


func match_elapsed() -> float:
	if mode == "rogue":
		return regulation_duration - time_left + rogue_extra_time
	if is_practice() and practice != null:
		return practice.elapsed
	return regulation_duration + overtime_count * OVERTIME_DURATION - time_left


func choose_minutes(minutes: int) -> bool:
	if mode != "free" or started or minutes < 5 or minutes > 15:
		return false
	match_minutes = minutes
	regulation_duration = minutes * 60.0
	time_left = regulation_duration
	return true


func choose_difficulty(index: int) -> bool:
	if mode != "free" or started or index < 0 or index >= Settings.NAMES.size():
		return false
	difficulty = index
	return true


func choose_ally_difficulty(index: int) -> bool:
	if mode != "free" or net != null or started or index < 0 or index >= Settings.NAMES.size():
		return false
	ally_difficulty = index
	return true


func ai_difficulty(team: int) -> int:
	if mode == "rogue":
		return Settings.Difficulty.HARD
	if net != null or team == 1:
		return difficulty
	return ally_difficulty if mode == "free" else Settings.Difficulty.NORMAL


func ai_profile(actor: Node3D) -> Dictionary:
	return Settings.PROFILES[ai_difficulty(actor.team)]


func ai_delay(actor: Node3D, key: String) -> float:
	var interval: Vector2 = ai_profile(actor)[key]
	return rng.randf_range(interval.x, interval.y)


func comeback_multiplier(team: int) -> float:
	return 1.0 + maxi(0, score[1 - team] - score[team]) * Gear.COMEBACK_PER_GOAL


func start_match() -> void:
	if mode == "rogue":
		if started:
			return
		rng.seed = rogue.seed_value + rogue.stage * 101
	tactics.reset(true)
	if mode == "conquest":
		rng.seed = Modes.CHALLENGES[challenge_id].seed
	started = true
	paused = false
	finished = false
	result_won = false
	score = [0, 0]
	team_upgrades = [[0, 0], [0, 0]]
	purchase_events.clear()
	e_purchase_events.clear()
	e_cast_events.clear()
	ability_casts = [0, 0, 0, 0, 0, 0]
	shots = 0
	goal_events = []
	loose_ball_seconds = 0.0
	stipend_clock = 0.0
	supply_clock = 0.0
	timeout_tokens = [1, 1]
	timeout_team = -1
	timeout_ai_wait = 3.0
	timeout_events.clear()
	money_message = ""
	money_message_time = 0.0
	regulation_duration = match_minutes * 60.0
	if mode == "rogue":
		regulation_duration = 90.0
		difficulty = rogue.difficulty()
		if rogue.ascension >= 5 and rogue.stage == rogue.STAGES:
			score = [0, 1]
		rogue.trim_rosters(self)
	if mode == "conquest":
		var rules: Dictionary = Modes.CHALLENGES[challenge_id]
		regulation_duration = rules.seconds
		difficulty = rules.difficulty
		score = rules.score.duplicate()
		while players.filter(func(a): return a.team == 0).size() > rules.team_size:
			var absent = players.filter(func(a): return a.team == 0 and not a.goalkeeper and a.shirt_number != 10).back()
			players.erase(absent)
			absent.free()
	time_left = regulation_duration
	overtime_count = 0
	rogue_extra_time = 0.0
	if is_practice():
		practice = Practice.new(self)
		practice.start()
		return
	team_formations[1] = Formations.opponent_formation(score[1] - score[0], rng)
	for team in range(2):
		assign_formation(team, not simulation_mode or mode == "rogue")
	for actor in players:
		actor.reset_position(true)
		actor.build_variant = rng.randi_range(0, Gear.NPC_BUILDS[actor.archetype].size() - 1)
	if mode == "rogue":
		rogue.apply_growth(self)
	var first_team: int = Modes.CHALLENGES[challenge_id].kickoff if mode == "conquest" else 0
	if mode == "rogue":
		first_team = (rogue.stage - 1) % 2
	reset_kickoff(first_team)
	if mode == "rogue":
		goal_pause = 2.0
	else:
		open_shop(first_team, "赛前准备")
	announce("蓝队向右进攻 → / 红队向左进攻 ←" if net != null else "你的主场。向右侧球门进攻 →", 3.5)
	if not simulation_mode and not agent_controlled:
		whistle_sound.play()


func reset_kickoff(team: int) -> void:
	kickoff_team = team
	tactics.reset()
	_clear_projectiles()
	for side in range(2):
		assign_formation(side)
	for actor in players:
		actor.reset_position()
		if not actor.human:
			actor.ai_think_wait = ai_delay(actor, "think")
	var forwards: Array = players.filter(func(a): return a.team == team and a.tactical_line == Formations.Line.FRONT)
	forwards.sort_custom(func(a, b): return absf(a.home.z) < absf(b.home.z))
	carrier = forwards[0]
	last_touch = carrier
	carrier.position = Vector3(-1.2 if team == 0 else 1.2, 0, 0)
	carrier.target = carrier.position
	ball.position = carrier.position + carrier.facing * carrier.control_distance() + Vector3.UP * Ball.RADIUS
	ball.velocity = Vector3.ZERO
	ball.trail_points.clear()
	ball.update_visual(0.0)
	possession_lock = 1.2
	possession_lock += carrier.equipment_bonus("protection")
	goal_pause = 0.0
	shop_open = false
	supply_shop = false
	timeout_team = -1
	marker_time = 0.0
	camera_focus = player.position
	if not simulation_mode:
		_update_camera(1.0)


func choose_role(kind: int) -> void:
	if mode == "rogue":
		return
	if mode == "tutorial" and kind != Roles.Kind.RUNNER:
		return
	if mode == "conquest" and Modes.CHALLENGES[challenge_id].role >= 0 and kind != Modes.CHALLENGES[challenge_id].role:
		return
	if is_practice() and started:
		return
	selected_role = kind
	player.human = false
	if not player.goalkeeper:
		player.set_archetype(Formations.random_hero(player.tactical_line, rng))
	var shirt := 1 if kind == Roles.Kind.KEEPER else 10
	player = players.filter(func(a): return a.team == 0 and a.shirt_number == shirt)[0]
	player.human = not simulation_mode
	player.set_archetype(kind)
	player.reset_position(true)
	if started:
		start_match()
	else:
		reset_kickoff(0)


func _unhandled_input(event: InputEvent) -> void:
	if net != null:
		net.handle_input(event)
		return
	if not started and event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if hud.settings_click(event.position):
			ui_interaction.emit("click")
			return
	if (not started or shop_open) and not paused and event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var formation_id: int = hud.formation_at(event.position)
		if formation_id >= 0:
			ui_interaction.emit("click")
			choose_formation(formation_id)
			return
	if shop_open and not paused and event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if hud.shop_click(event.position):
			ui_interaction.emit("click")
			return
		var item_id: int = hud.shop_item_at(event.position)
		var slot: int = hud.inventory_slot_at(event.position)
		if item_id >= 0:
			ui_interaction.emit("click")
			var reason := purchase_error(player, item_id)
			if buy_item(player, item_id):
				shop_feedback = ("已升级「%s」· 全队立即生效" if Gear.ITEMS[item_id].has("team_upgrade") else "已装备「%s」") % Gear.ITEMS[item_id].name
			else:
				shop_feedback = reason
		elif slot >= 0 and slot < player.inventory.size():
			ui_interaction.emit("click")
			var sold_name: String = Gear.ITEMS[player.inventory[slot]].name
			sell_item(player, slot)
			shop_feedback = "已出售「%s」· 返还 70%% 金钱" % sold_name
		return
	if event is InputEventKey and event.physical_keycode == KEY_W and not event.pressed:
		if is_playing():
			release_ability(player)
		else:
			player.cancel_charge()
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if (not started or paused or finished) and event.physical_keycode in [KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6]:
			choose_role(event.physical_keycode - KEY_1)
			return
		match event.physical_keycode:
			KEY_ENTER:
				if not started or finished:
					start_match()
				elif shop_open and not paused:
					ui_interaction.emit("confirm")
					skip_shop()
			KEY_ESCAPE:
				if started and not finished and not (shop_open and timeout_team >= 0):
					paused = not paused
					if paused:
						player.cancel_charge()
			KEY_H:
				help_visible = not help_visible
			KEY_P:
				var reason := timeout_error(player.team)
				if not request_timeout(player.team):
					announce(reason, 2.0)
			KEY_R:
				if started and mode != "rogue":
					start_match()
			KEY_Y:
				camera_locked = not camera_locked
			KEY_TAB:
				overview = not overview
			KEY_SPACE:
				camera_locked = true
				overview = false
		if not is_playing():
			return
		match event.physical_keycode:
			KEY_Q:
				player_kick()
			KEY_E:
				var point: Variant = ground_point(get_viewport().get_mouse_position())
				if not use_e(player, point):
					announce(e_use_error(player), 1.5)
			KEY_W:
				if player.archetype == Roles.Kind.WARDEN:
					var target_point: Variant = ground_point(get_viewport().get_mouse_position())
					if target_point != null:
						use_ability(player, Vector3.ZERO, target_point)
					return
				var direction: Vector3 = player.facing
				if player.archetype == Roles.Kind.STRIKER:
					var point: Variant = ground_point(get_viewport().get_mouse_position())
					if point != null and player.position.distance_to(point) > 0.1:
						direction = (point - player.position).normalized()
				use_ability(player, direction)
			KEY_S:
				player.target = player.position
				player.velocity = Vector3.ZERO
	if event is InputEventMouseButton and event.pressed:
		if not started or finished:
			if event.button_index == MOUSE_BUTTON_LEFT:
				var card: int = hud.role_card_at(event.position)
				if not started and card >= 0:
					ui_interaction.emit("click")
					choose_role(card)
				else:
					start_match()
			return
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			zoom_size = maxf(30.0, zoom_size - 3.0)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			zoom_size = minf(63.0, zoom_size + 3.0)
		elif is_playing():
			if event.button_index == MOUSE_BUTTON_RIGHT:
				command_move(event.position)
			elif event.button_index == MOUSE_BUTTON_LEFT and not player.action_blocked():
				var point: Variant = ground_point(event.position)
				if point != null:
					var direction: Vector3 = point - player.position
					direction.y = 0.0
					if direction.length() > 0.2:
						player.target = player.position
						player.velocity = Vector3.ZERO
						player.facing = direction.normalized()


func is_playing() -> bool:
	return started and not paused and not finished and goal_pause <= 0.0


func is_practice() -> bool:
	return mode in ["training", "tutorial"]


func finish_session(won: bool) -> void:
	tactics.end_flight("ended")
	tactics.end_keeper_hold("ended")
	finished = true
	result_won = won
	shop_open = false
	goal_pause = 0.0
	session_finished.emit(won)


func timeout_error(team: int) -> String:
	if mode not in ["free", "conquest"]:
		return "本模式不使用战术暂停"
	if not is_playing() or shop_open:
		return "请在比赛进行中申请暂停"
	if carrier == null or carrier.team != team:
		return "仅本队控球时可申请暂停"
	if timeout_tokens[team] <= 0:
		return "暂无暂停次数 · 每 90 秒补充一次"
	return ""


func request_timeout(team: int, by_ai: bool = false) -> bool:
	if not timeout_error(team).is_empty():
		return false
	timeout_tokens[team] -= 1
	timeout_team = team
	timeout_ai_wait = 12.0
	timeout_events.append({"time": match_elapsed(), "team": team, "ai": by_ai})
	open_shop(team, "%s%s · 战术暂停" % ["蓝队" if team == 0 else "红队", " AI" if by_ai else ""])
	return true


func _update_timeout_supply(delta: float) -> void:
	supply_clock += delta
	while supply_clock >= Gear.SUPPLY_SECONDS:
		supply_clock -= Gear.SUPPLY_SECONDS
		for team in range(2):
			timeout_tokens[team] = mini(2, timeout_tokens[team] + 1)
		announce("战术暂停 +1 · 本队控球时按 P 使用", 2.5)


func _try_ai_timeout(delta: float) -> void:
	timeout_ai_wait = maxf(0.0, timeout_ai_wait - delta)
	if timeout_ai_wait > 0 or carrier == null or match_elapsed() < 30.0:
		return
	timeout_ai_wait = 3.0
	var team: int = carrier.team
	if not timeout_error(team).is_empty() or possession_lock > 0.0:
		return
	# Shop from settled possession; do not interrupt a promising attack.
	if carrier.position.x * (1 if team == 0 else -1) > 12.0 or tactics.pressure(carrier) < 4.0:
		return
	if timeout_tokens[team] < 2 and players.any(func(a): return a.team == team and a.human):
		return # Keep the human team's final token available to its player.
	var buyers := 0
	for actor in players:
		if actor.team != team or actor.human or actor.gold < 300:
			continue
		var plan: Array = Gear.NPC_BUILDS[actor.archetype][actor.build_variant]
		if plan.any(func(id): return id not in actor.inventory and Gear.buy_cost(actor.inventory, id) <= actor.gold):
			buyers += 1
	if buyers >= 2:
		request_timeout(team, true)


func open_shop(team: int, title: String, resume_play: bool = false) -> void:
	if mode == "rogue":
		return
	supply_shop = resume_play
	if not supply_shop:
		_clear_projectiles()
	for side in ([1] if net == null else [0, 1]):
		if (net == null or not players.any(func(a): return a.team == side and a.human)) and (match_elapsed() > 0.0 or score != [0, 0]):
			team_formations[side] = Formations.opponent_formation(score[side] - score[1 - side], rng)
		assign_formation(side)
	kickoff_team = team
	shop_open = true
	if net != null:
		net.shop_opened()
	shop_title = title
	shop_feedback = "材料原价抵扣 · 点击装备购买 / 合成 · 已装备物品点击出售"
	goal_pause = Gear.SHOP_SECONDS
	npc_shopped = false
	if supply_shop:
		return
	for actor in players:
		actor.cancel_charge()
		actor.ability_time = 0.0
		actor.dash_remaining = 0.0
		actor.slow_multiplier = 1.0
		actor.stun_time = 0.0
		actor.throw_windup = 0.0
		actor.save_time = 0.0
		actor.e_boost_time = 0.0
		actor.e_immunity_time = 0.0


func skip_shop() -> void:
	if not shop_open or paused:
		return
	if not npc_shopped and not is_practice():
		_npc_shop()
		npc_shopped = true
	close_shop()


func close_shop() -> void:
	if supply_shop:
		goal_pause = 0.0
		shop_open = false
		supply_shop = false
	else:
		reset_kickoff(kickoff_team)


func purchase_error(actor: Node3D, item_id: int) -> String:
	if mode == "rogue":
		return "远征通过胜利天赋成长"
	if paused:
		return "暂停中"
	if not shop_open or finished:
		return "仅购买阶段可交易"
	if item_id < 0 or item_id >= Gear.ITEMS.size():
		return "无效装备"
	var item: Dictionary = Gear.ITEMS[item_id]
	if item.tier == 1 and item_id in actor.inventory:
		return "已装备"
	if item.role >= 0 and item.role != actor.archetype:
		return "职业不符"
	if item.has("team_upgrade") and team_upgrades[actor.team][item.team_upgrade] >= Gear.TEAM_UPGRADE_CAP:
		return "本队已达 %d 次上限" % Gear.TEAM_UPGRADE_CAP
	if not item.has("team_upgrade") and actor.inventory.size() - Gear.components_owned(actor.inventory, item_id).size() >= Gear.SLOTS:
		return "装备栏已满"
	var cost := Gear.buy_cost(actor.inventory, item_id)
	if actor.gold < cost:
		return "还差 %d 金" % (cost - actor.gold)
	return ""


func buy_item(actor: Node3D, item_id: int) -> bool:
	if not purchase_error(actor, item_id).is_empty():
		return false
	var cost := Gear.buy_cost(actor.inventory, item_id)
	var components := Gear.components_owned(actor.inventory, item_id)
	actor.gold -= cost
	if Gear.ITEMS[item_id].has("team_upgrade"):
		var upgrade: int = Gear.ITEMS[item_id].team_upgrade
		team_upgrades[actor.team][upgrade] += 1
		actor.team_purchases[upgrade] += 1
		for teammate in players:
			teammate.team_speed_multiplier = team_speed(teammate.team)
	else:
		for component in components:
			actor.inventory.erase(component)
		actor.inventory.append(item_id)
		actor.refresh_equipment()
	purchase_events.append({"time": match_elapsed(), "team": actor.team,
		"shirt_number": actor.shirt_number, "role": actor.archetype,
		"item": item_id, "cost": cost, "components": components})
	return true


func team_speed(team: int) -> float:
	return pow(Gear.TEAM_SPEED_GAIN, team_upgrades[team][0]) * pow(Gear.TEAM_SPEED_LOSS, team_upgrades[1 - team][1])


func sell_item(actor: Node3D, slot: int) -> bool:
	if not shop_open or paused or finished or slot < 0 or slot >= actor.inventory.size():
		return false
	actor.gold += Gear.sell_price(actor.inventory[slot])
	actor.inventory.remove_at(slot)
	actor.refresh_equipment()
	return true


func _npc_shop() -> void:
	if mode == "rogue":
		return
	for actor in players:
		if actor.human:
			continue
		# One charge per shop if needed; retain a first component before spending on E.
		var skill_id: int = ESkills.NPC_SKILLS[actor.archetype][actor.build_variant]
		if not actor.inventory.is_empty() and actor.e_charges.get(skill_id, 0) == 0:
			buy_e(actor, skill_id)
		for item_id in Gear.NPC_BUILDS[actor.archetype][actor.build_variant]:
			if item_id in actor.inventory:
				continue
			if buy_item(actor, item_id):
				continue
			var needed: Array = Gear.ITEMS[item_id].recipe.duplicate()
			for owned in Gear.components_owned(actor.inventory, item_id):
				needed.erase(owned)
			for component in needed:
				if not buy_item(actor, component):
					break
			break
		if actor.e_charges.get(skill_id, 0) == 0 and not actor.inventory.is_empty():
			buy_e(actor, skill_id)
		# Six completed personal items before permanent team purchases.
		if actor.inventory.size() == Gear.SLOTS and actor.inventory.all(func(id): return Gear.ITEMS[id].tier == 1):
			while actor.gold >= Gear.ITEMS[Gear.TEAM_BOOTS].cost:
				var item_id: int = Gear.TEAM_BOOTS if (actor.shirt_number + actor.team_purchases[0] + actor.team_purchases[1]) % 2 == 0 else Gear.TEAM_SCYTHE
				if team_upgrades[actor.team][Gear.ITEMS[item_id].team_upgrade] >= Gear.TEAM_UPGRADE_CAP:
					item_id = Gear.TEAM_SCYTHE if item_id == Gear.TEAM_BOOTS else Gear.TEAM_BOOTS
				if not buy_item(actor, item_id):
					break


func e_purchase_error(actor: Node3D, skill_id: int) -> String:
	if mode == "rogue":
		return "远征通过天赋学习技能"
	if not shop_open or paused or finished:
		return "仅未暂停的商店可购买"
	if skill_id < 0 or skill_id >= ESkills.SKILLS.size():
		return "无效技能"
	var skill: Dictionary = ESkills.SKILLS[skill_id]
	if skill.role >= 0 and skill.role != actor.archetype:
		return "英雄不符"
	if actor.gold < skill.cost:
		return "还差 %d 金" % (skill.cost - actor.gold)
	return ""


func buy_e(actor: Node3D, skill_id: int) -> bool:
	if not e_purchase_error(actor, skill_id).is_empty():
		return false
	actor.gold -= ESkills.SKILLS[skill_id].cost
	actor.e_charges[skill_id] = actor.e_charges.get(skill_id, 0) + 1
	actor.e_selected = skill_id
	e_purchase_events.append({"time": match_elapsed(), "team": actor.team, "shirt_number": actor.shirt_number,
		"skill": skill_id, "cost": ESkills.SKILLS[skill_id].cost})
	return true


func equip_e(actor: Node3D, skill_id: int) -> bool:
	if not shop_open or paused or finished or skill_id not in ESkills.visible_skills(actor.archetype) or actor.e_charges.get(skill_id, 0) <= 0:
		return false
	actor.e_selected = skill_id
	return true


func e_use_error(actor: Node3D) -> String:
	if not is_playing():
		return "比赛进行时才能释放 E"
	var id: int = actor.e_selected
	if actor.rogue_player and id < 0:
		return "尚未学习 E · 胜利后可选技能天赋"
	if id not in ESkills.visible_skills(actor.archetype) or (not actor.e_unlimited and actor.e_charges.get(id, 0) <= 0):
		return "E 次数不足 · 商店购买"
	if actor.e_cooldown > 0.0:
		return "E 冷却 %.1f 秒" % actor.e_cooldown
	if actor.charging or actor.dash_remaining > 0.0 or actor.throw_windup > 0.0 or (actor.stun_time > 0.0 and id != ESkills.Kind.CLEANSE):
		return "当前动作无法释放 E"
	if id == ESkills.Kind.CONTROL and carrier != actor:
		return "护球需要自己持球"
	return ""


func use_e(actor: Node3D, point: Variant = null) -> bool:
	if not e_use_error(actor).is_empty():
		return false
	var id: int = actor.e_selected
	match id:
		ESkills.Kind.HASTE:
			grant_boost(actor, 1.10 + rogue.e_quality * 0.02 if actor.rogue_player else 1.2, 1.8 if actor.rogue_player else 3.0)
		ESkills.Kind.CLEANSE:
			grant_immunity(actor, 0.7 + rogue.e_quality * 0.2 if actor.rogue_player else 2.0)
		ESkills.Kind.CONTROL:
			possession_lock = maxf(possession_lock, 0.6 + rogue.e_quality * 0.15 if actor.rogue_player else 1.3)
		ESkills.Kind.RUNNER:
			grant_boost(actor, 1.25, 3.0)
		ESkills.Kind.GUARD:
			create_field(actor, actor.position, 6.0, 4.0, 0.6, "震荡")
		ESkills.Kind.CHARGER:
			if point == null:
				return false
			var destination: Vector3 = actor.constrain_position(field_point(actor, point, 5.0))
			if destination.distance_to(actor.position) < 0.1:
				return false
			actor.facing = (destination - actor.position).normalized()
			actor.position = destination
			actor.target = destination
			actor.velocity = Vector3.ZERO
			if carrier == actor:
				ball.position = actor.position + actor.facing * actor.control_distance() + Vector3.UP * Ball.RADIUS
				ball.velocity = Vector3.ZERO
		ESkills.Kind.STRIKER:
			for ally in players:
				if ally.team == actor.team and ally.position.distance_to(actor.position) <= 8.0:
					grant_boost(ally, 1.18, 4.0)
		ESkills.Kind.KEEPER:
			actor.save_time = maxf(actor.save_time, 2.0)
			grant_immunity(actor, 2.0)
		ESkills.Kind.WARDEN:
			for ally in players:
				if ally.team == actor.team and ally.position.distance_to(actor.position) <= 8.0:
					grant_immunity(ally, 2.5)
	if not actor.e_unlimited:
		actor.e_charges[id] -= 1
	actor.e_cooldown = rogue.E_COOLDOWNS[id] / (1.0 + actor.equipment_bonus("haste")) if actor.rogue_player else ESkills.SKILLS[id].cooldown
	actor.stats.e_casts += 1
	actor.ai_e_wait = -1.0
	e_cast_events.append({"time": match_elapsed(), "team": actor.team, "shirt_number": actor.shirt_number, "skill": id})
	if actor.human:
		announce("E %s · 冷却后可再用" % ESkills.SKILLS[id].name if actor.e_unlimited else "E %s · 剩余 %d 次" % [ESkills.SKILLS[id].name, actor.e_charges[id]], 1.5)
	return true


func grant_boost(actor: Node3D, multiplier: float, seconds: float) -> void:
	# A weaker support boost cannot extend an existing stronger sprint.
	if actor.e_boost_time <= 0.0 or multiplier > actor.e_boost_multiplier:
		actor.e_boost_multiplier = multiplier
		actor.e_boost_time = seconds
	elif is_equal_approx(multiplier, actor.e_boost_multiplier):
		actor.e_boost_time = maxf(actor.e_boost_time, seconds)


func grant_immunity(actor: Node3D, seconds: float) -> void:
	actor.stun_time = 0.0
	actor.slow_multiplier = 1.0
	actor.e_immunity_time = maxf(actor.e_immunity_time, seconds)


func _ai_wants_e(actor: Node3D) -> bool:
	if not e_use_error(actor).is_empty():
		return false
	var distance: float = actor.position.distance_to(ball.position)
	match actor.e_selected:
		ESkills.Kind.CLEANSE:
			return actor.stun_time > 0.0 or actor.slow_multiplier < 0.95
		ESkills.Kind.HASTE, ESkills.Kind.RUNNER, ESkills.Kind.CHARGER:
			if actor.archetype == Roles.Kind.RUNNER and actor.ability_time > 0.0:
				return false
			return actor.target.distance_to(actor.position) > 5.0 and distance < 22.0
		ESkills.Kind.CONTROL, ESkills.Kind.GUARD:
			return (actor.e_selected != ESkills.Kind.CONTROL or carrier == actor) and players.any(func(p): return p.team != actor.team and p.position.distance_to(actor.position) < 5.0)
		ESkills.Kind.STRIKER:
			return carrier != null and carrier.team == actor.team and distance < 8.0
		ESkills.Kind.KEEPER:
			return carrier == null and ball.velocity.length() > 7.0 and distance < 10.0
		ESkills.Kind.WARDEN:
			return players.any(func(p): return p.team == actor.team and p.position.distance_to(actor.position) <= 8.0 and (p.stun_time > 0.0 or p.slow_multiplier < 0.95))
	return false


func _update_ai_e(actor: Node3D, delta: float) -> void:
	if actor.ai_e_wait >= 0.0:
		actor.ai_e_wait -= delta
		if actor.ai_e_wait <= 0.0:
			actor.ai_e_wait = -1.0
			if _ai_wants_e(actor):
				use_e(actor, actor.target)
	elif actor.ai_think_wait <= delta and _ai_wants_e(actor):
		actor.ai_e_wait = ai_delay(actor, "skill")


func field_point(actor: Node3D, point: Vector3, reach: float) -> Vector3:
	point.y = 0.0
	point = actor.position + (point - actor.position).limit_length(reach)
	return Vector3(clampf(point.x, -48, 48), 0, clampf(point.z, -30, 30))


func create_field(actor: Node3D, point: Vector3, radius: float, seconds: float, multiplier: float, title: String) -> void:
	var field := AreaField.new()
	field.source = actor
	field.team = actor.team
	field.position = point
	field.radius = radius
	field.remaining = seconds
	field.multiplier = multiplier
	field.title = title
	field.visuals_enabled = not simulation_mode
	add_child(field)
	fields.append(field)


func _update_fields(delta: float) -> void:
	for i in range(fields.size() - 1, -1, -1):
		var field = fields[i]
		field.remaining -= delta
		if field.remaining <= 0.0:
			field.free()
			fields.remove_at(i)
		else:
			field.update_label()


func award_money(actor: Node3D, amount: int, reason: String) -> void:
	if mode == "rogue":
		return
	actor.gold += amount
	actor.stats.gold_earned += amount
	if actor.human:
		money_message = "%s +%d 金" % [reason, amount]
		money_message_time = 3.0


func _defense_income(actor: Node3D, amount: int, reason: String) -> void:
	if actor.defense_reward_wait <= 0.0:
		award_money(actor, amount, reason)
		actor.defense_reward_wait = Gear.DEFENSE_REWARD_COOLDOWN


func _update_economy(delta: float) -> void:
	for actor in players:
		actor.defense_reward_wait = maxf(0.0, actor.defense_reward_wait - delta)
	stipend_clock += delta
	while stipend_clock >= Gear.STIPEND_SECONDS:
		stipend_clock -= Gear.STIPEND_SECONDS
		for actor in players:
			award_money(actor, Gear.STIPEND_GOLD, "比赛津贴")
	if carrier != null:
		carrier.possession_income += delta
		while carrier.possession_income >= Gear.POSSESSION_SECONDS:
			carrier.possession_income -= Gear.POSSESSION_SECONDS
			award_money(carrier, Gear.POSSESSION_GOLD, "累计控球 5 秒")


func ground_point(screen: Vector2) -> Variant:
	# Camera ray picking follows Godot's MIT-licensed 3D navigation demo.
	return Plane(Vector3.UP, 0.0).intersects_ray(camera.project_ray_origin(screen), camera.project_ray_normal(screen))


func command_move(screen: Vector2) -> void:
	var point: Variant = ground_point(screen)
	if point == null:
		return
	player.target = player.constrain_position(point)
	marker.position = player.target + Vector3.UP * 0.07
	marker_time = 0.65


func player_kick() -> void:
	actor_kick(player)


func actor_kick(actor: Node3D) -> void:
	if actor.kick_cooldown > 0 or actor.action_blocked():
		return
	if actor.archetype == Roles.Kind.KEEPER and carrier != actor:
		keeper_save(actor)
		return
	var flat_ball := Vector3(ball.position.x, 0, ball.position.z)
	if carrier != actor and (actor.position.distance_to(flat_ball) > 1.85 * actor.hit_scale() or ball.position.y > 1.3 * actor.hit_scale()):
		announce("靠近足球后按 Q 踢球", 1.2)
		return
	kick_ball(actor, actor.facing, 29.0)
	actor.kick_cooldown = KICK_COOLDOWN


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and player != null and not agent_controlled:
		if net != null:
			net.order("cancel")
		player.cancel_charge()


func use_ability(actor: Node3D, direction: Vector3 = Vector3.ZERO, point: Variant = null) -> bool:
	if not actor.w_unlocked:
		return false
	var kind: int = actor.archetype
	if actor.ability_cooldown > 0 or actor.charging or actor.dash_remaining > 0 or actor.action_blocked():
		return false
	if kind == Roles.Kind.CHARGER:
		actor.charging = true
		actor.charge_time = 0.0
		return true
	if kind == Roles.Kind.WARDEN:
		if point == null:
			return false
		var destination := field_point(actor, point, actor.domain_range())
		create_field(actor, destination, actor.domain_radius(), Roles.DURATION[kind], 0.7, "镇守领域")
	if kind == Roles.Kind.STRIKER:
		var shot := SkillProjectile.new()
		shot.source = actor
		shot.direction = actor.facing if direction.is_zero_approx() else direction.normalized()
		shot.position = actor.position
		shot.radius = actor.throw_radius()
		shot.speed = actor.throw_speed()
		shot.remaining = actor.throw_range()
		shot.stun_seconds = actor.throw_stun()
		shot.mobile_cast = actor.mobile_throw()
		shot.visuals_enabled = not simulation_mode
		add_child(shot)
		projectiles.append(shot)
		actor.facing = shot.direction
		actor.throw_windup = Roles.THROW_WINDUP
		actor.ai_kick_power = 0.0
		if not shot.mobile_cast:
			actor.velocity = Vector3.ZERO
	actor.ability_time = actor.ability_duration()
	actor.ability_cooldown = actor.ability_max_cooldown()
	actor.ai_skill_wait = 0.6
	ability_casts[kind] += 1
	actor.stats.casts += 1
	return true


func release_ability(actor: Node3D) -> bool:
	if not actor.charging or actor.action_blocked():
		return false
	actor.dash_remaining = actor.dash_distance()
	actor.dash_direction = actor.facing
	actor.cancel_charge()
	actor.ability_cooldown = actor.ability_max_cooldown()
	actor.ai_skill_wait = 0.6
	ability_casts[actor.archetype] += 1
	actor.stats.casts += 1
	return true


func kick_ball(actor: Node3D, direction: Vector3, power: float) -> void:
	if actor.action_blocked():
		return
	actor.ai_kick_power = 0.0
	carrier = null
	last_touch = actor
	possession_lock = 0.22
	ball.position = actor.position + direction.normalized() * (actor.control_distance() + 0.05) + Vector3.UP * Ball.RADIUS
	ball.velocity = direction.normalized() * power + Vector3.UP * (2.8 if power > 24 else 1.0)
	if actor.ai_kick_kind == "keeper_clear":
		ball.velocity.y = 5.0
	ball.velocity.x *= 1.0 + actor.equipment_bonus("kick")
	ball.velocity.z *= 1.0 + actor.equipment_bonus("kick")
	actor.facing = direction.normalized()
	actor.kick_pose = 1.0
	actor.kick_cooldown = 0.6
	tactics.on_kick(actor, direction.normalized())
	actor.ai_poke = false
	shots += 1
	actor.stats.kicks += 1
	if not simulation_mode and not agent_controlled:
		kick_sound.pitch_scale = randf_range(0.9, 1.12)
		kick_sound.play()


func keeper_save(actor: Node3D) -> bool:
	if actor.archetype != Roles.Kind.KEEPER or actor.kick_cooldown > 0 or actor.action_blocked():
		return false
	actor.save_time = actor.save_window()
	actor.kick_cooldown = Roles.SAVE_COOLDOWN
	actor.stats.save_attempts += 1
	return true


func _in_keeper_cone(actor: Node3D, point: Vector3) -> bool:
	var offset := point - actor.position
	offset.y = 0.0
	return offset.length() <= actor.keeper_radius() and (offset.is_zero_approx() or actor.facing.dot(offset.normalized()) >= cos(Roles.KEEPER_CONE_HALF_ANGLE))


func _throw_target(actor: Node3D) -> Node3D:
	var nearest: Node3D = null
	var distance: float = actor.throw_range() - 2.0
	for opponent in players:
		if opponent.team == actor.team or opponent.stun_time > 0.0:
			continue
		var gap: float = actor.position.distance_to(opponent.position)
		if opponent == carrier and gap < actor.throw_range() - 2.0:
			return opponent
		var relevant: bool = opponent.position.distance_to(ball.position) < 4.0
		if (net != null or actor.team == 1) and difficulty == Settings.Difficulty.HARD and opponent.human and goal_threat(actor.team, opponent.position) > 0.2:
			relevant = true
		if carrier == actor:
			relevant = gap < 8.0 and (opponent.position - actor.position).dot(actor.facing) > 0.0
		if not relevant:
			continue
		if gap < distance:
			distance = gap
			nearest = opponent
	return nearest


func _avoid_warning(actor: Node3D) -> void:
	# Perception occurs on the existing 0.25–0.45 s thinking tick.
	for shot in projectiles:
		if shot.source.team == actor.team or shot.windup <= 0.0:
			continue
		var offset: Vector3 = actor.position - shot.position
		var along: float = offset.dot(shot.direction)
		var side := Vector3(-shot.direction.z, 0, shot.direction.x)
		var lateral: float = offset.dot(side)
		if along > 0 and along < shot.remaining and absf(lateral) < shot.radius + actor.collision_radius() + 0.5:
			var dodge: float = shot.radius + actor.collision_radius() + 1.5
			actor.target = actor.constrain_position(actor.position + side * (dodge if lateral >= 0 else -dodge))
			return


func _clear_projectiles() -> void:
	for shot in projectiles:
		shot.free()
	projectiles.clear()
	for field in fields:
		field.free()
	fields.clear()


func _update_projectiles(delta: float) -> void:
	for i in range(projectiles.size() - 1, -1, -1):
		var shot = projectiles[i]
		if shot.windup > 0.0:
			if shot.source.stun_time > 0.0:
				shot.source.throw_windup = 0.0
				shot.free()
				projectiles.remove_at(i)
				continue
			if shot.mobile_cast:
				shot.position = shot.source.position
			shot.windup = maxf(0.0, shot.windup - delta)
			if shot.windup <= 0.0:
				shot.show_flight()
			continue
		var travel: float = minf(shot.speed * delta, shot.remaining)
		var from: Vector3 = shot.position
		var to: Vector3 = from + shot.direction * travel
		var victim: Node3D = null
		var earliest := INF
		for opponent in players:
			if opponent.team == shot.source.team:
				continue
			var nearest := Geometry3D.get_closest_point_to_segment(opponent.position, from, to)
			if nearest.distance_to(opponent.position) <= shot.radius + opponent.collision_radius():
				var distance := nearest.distance_to(from)
				if distance < earliest:
					earliest = distance
					victim = opponent
		shot.position = to
		shot.remaining -= travel
		if victim != null and victim.e_immunity_time <= 0.0:
			var stun_seconds: float = shot.stun_seconds * (1.0 - victim.equipment_bonus("stun_resist"))
			shot.source.stats.stun_seconds += maxf(0.0, stun_seconds - victim.stun_time)
			victim.stun_time = maxf(victim.stun_time, stun_seconds)
			victim.cancel_charge()
			victim.dash_remaining = 0.0
			victim.velocity = Vector3.ZERO
			victim.ai_kick_power = 0.0
			victim.ai_skill_pending = false
			victim.ai_save_wait = -1.0
			victim.save_time = 0.0
			shot.source.stats.stuns += 1
			award_money(shot.source, Gear.STUN_GOLD, "眩晕命中")

		if victim != null or shot.remaining <= 0.0:
			shot.free()
			projectiles.remove_at(i)


func _physics_process(delta: float) -> void:
	if net != null and not net.hosting:
		return
	if not started or paused or finished:
		return
	announcement_time = maxf(0.0, announcement_time - delta)
	money_message_time = maxf(0.0, money_message_time - delta)
	if goal_pause > 0:
		if is_practice():
			return
		goal_pause -= delta
		if shop_open and not npc_shopped and goal_pause <= Gear.SHOP_SECONDS - 1.0:
			_npc_shop()
			npc_shopped = true
		if goal_pause <= 0:
			close_shop()
			announce("蓝队 → / 红队 ←" if net != null else "向右侧球门进攻 →", 1.5)
		return
	var golden_goal := mode == "rogue" and overtime_count > 0
	var elapsed := delta if is_practice() or golden_goal else minf(delta, time_left)
	if not is_practice() and mode != "rogue":
		_update_timeout_supply(elapsed)
		_update_economy(elapsed)
	if carrier != null:
		carrier.stats.possession_seconds += elapsed
	else:
		loose_ball_seconds += elapsed
	if golden_goal:
		rogue_extra_time += delta
	elif not is_practice():
		time_left = maxf(0.0, time_left - delta)
	if time_left <= 0.0 and not golden_goal:
		if mode == "rogue":
			if score[0] != score[1]:
				finish_session(score[0] > score[1])
			else:
				overtime_count = 1
				reset_kickoff(rogue.stage % 2)
				goal_pause = 2.0
				announce("金球加时 · 下一球决定胜负", 4.0)
			return
		if mode == "conquest":
			finish_session(Modes.outcome(challenge_id, score, true) == 1)
			return
		if score[0] == score[1]:
			overtime_count += 1
			time_left = OVERTIME_DURATION
			reset_kickoff(overtime_count % 2)
			goal_pause = 2.0
			announce("平局 · 第 %d 次加时，追加 2 分钟" % overtime_count, 3.0)
		else:
			finish_session(score[0] > score[1])
		if not simulation_mode and not agent_controlled:
			whistle_sound.play()
		return
	possession_lock = maxf(0.0, possession_lock - delta)
	if net == null and not simulation_mode and not agent_controlled and Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		command_move(get_viewport().get_mouse_position())
	if not is_practice():
		_update_ai(delta)
	_update_fields(delta)
	_apply_slow_fields(delta)
	for actor in players:
		actor.step(delta, players)
	_update_projectiles(delta)
	_update_possession(delta)
	_check_boundaries()
	if is_practice():
		practice.update(delta)
		return
	if mode == "conquest":
		var outcome := Modes.outcome(challenge_id, score, false)
		if outcome >= 0:
			finish_session(outcome == 1)
			return
	if mode != "rogue" and is_playing():
		_try_ai_timeout(delta)


func _update_ai(delta: float) -> void:
	tactics.tick(delta)
	# Execute already planned actions smoothly; only observe/replan on a think tick.
	var thinking: Array = []
	for actor in players:
		if actor.human:
			continue
		actor.ai_think_wait = maxf(0.0, actor.ai_think_wait - delta)
		_update_ai_e(actor, delta)
		if actor.action_blocked():
			continue
		if actor.ai_save_wait >= 0.0:
			actor.ai_save_wait -= delta
			if actor.ai_save_wait <= 0.0:
				actor.ai_save_wait = -1.0
				if carrier == null and actor.position.distance_to(ball.position) < Roles.SAVE_REACH + 4.0:
					keeper_save(actor)
		if actor.ai_kick_power > 0.0:
			if actor.ai_pass_target != null and actor.ai_think_wait <= 0.0:
				tactics.refresh_pass(actor)
			actor.ai_kick_wait = maxf(0.0, actor.ai_kick_wait - delta)
			if (actor.ai_poke and not tactics.can_poke(actor)) or (not actor.ai_poke and carrier != actor):
				actor.ai_kick_power = 0.0
				actor.ai_poke = false
				actor.ai_pass_target = null
				actor.ai_kick_kind = "shot"
			elif actor.ai_kick_wait <= 0.0 and actor.kick_cooldown <= 0.0 and actor.facing.angle_to(actor.ai_aim_direction) <= deg_to_rad(2.0):
				kick_ball(actor, actor.facing, actor.ai_kick_power)
		if actor.ai_skill_pending and actor.ai_skill_wait <= 0.0:
			actor.ai_skill_pending = false
			var direction: Vector3 = actor.facing
			if actor.archetype == Roles.Kind.STRIKER:
				var victim := _throw_target(actor)
				if victim != null:
					direction = (victim.position + victim.velocity * 0.2 - actor.position).normalized().rotated(Vector3.UP, deg_to_rad(rng.randf_range(-ai_profile(actor).shot_error, ai_profile(actor).shot_error)))
			var point: Variant = _ai_domain_target(actor) if actor.archetype == Roles.Kind.WARDEN else ball.position + Vector3(ball.velocity.x, 0, ball.velocity.z) * 0.25
			if point != null and _ai_wants_ability(actor, actor.ai_contesting) and use_ability(actor, direction, point):
				if actor.archetype == Roles.Kind.CHARGER:
					actor.ai_charge_goal = rng.randf_range(actor.max_charge_time() * Roles.AI_CHARGE_MIN_FRACTION, actor.max_charge_time())
		if actor.charging and actor.charge_time >= actor.ai_charge_goal:
			release_ability(actor)
		if actor.ai_think_wait <= 0.0:
			actor.ai_think_wait = ai_delay(actor, "think")
			if not tactics.flight.is_empty() and tactics.flight.to == actor:
				actor.ai_think_wait = minf(actor.ai_think_wait, NPCTactics.TUNE.receive_delay + rng.randf_range(0.0, 0.06))
			actor.ai_turn_error = deg_to_rad(rng.randf_range(-ai_profile(actor).turn_error, ai_profile(actor).turn_error))
			actor.ai_turn_speed = deg_to_rad(ai_delay(actor, "turn_speed"))
			thinking.append(actor)
	if thinking.is_empty():
		return
	var ball_flat := Vector3(ball.position.x, 0, ball.position.z)
	var defensive_targets := [_defensive_targets(0, ball_flat), _defensive_targets(1, ball_flat)]
	if net == null:
		_add_player_coverage(defensive_targets[1])
	else:
		for human in players.filter(func(a): return a.human):
			_add_player_coverage(defensive_targets[1 - human.team], human)
	var chasers: Array = [[], []]
	for team in range(2):
		var nearest: Array = []
		for actor in players:
			if actor.team == team and not actor.human and not actor.goalkeeper and not defensive_targets[team].has(actor):
				nearest.append(actor)
		nearest.sort_custom(func(a, b): return a.position.distance_squared_to(ball_flat) < b.position.distance_squared_to(ball_flat))
		var pressing := 0
		for point in defensive_targets[team].values():
			if point.distance_to(ball_flat) < 4.0:
				pressing += 1
		chasers[team] = nearest.slice(0, maxi(0, chaser_count(team) - pressing))
		if not tactics.flight.is_empty() and tactics.flight.from.team == team:
			chasers[team] = []
	for actor in thinking:
		if actor.dash_remaining > 0 or actor.ai_kick_power > 0 or actor.action_blocked():
			continue
		var attack := 1.0 if actor.team == 0 else -1.0
		if carrier == actor:
			tactics.attack(actor)
			_try_ai_ability(actor, true)
			_avoid_warning(actor)
			continue
		if tactics.receive_target(actor):
			continue
		if tactics.try_poke(actor):
			continue
		if actor.goalkeeper:
			actor.target = Vector3(-attack * 44.7, 0, clampf(ball.position.z * 0.28, -4.1, 4.1))
			if ball_flat.distance_to(actor.position) < 9.0 and (carrier == null or carrier.team != actor.team):
				actor.target = Vector3(clampf(ball_flat.x, -46.6, 46.6), 0, clampf(ball_flat.z, -10, 10))
			var approaching: bool = ball.velocity.dot(actor.position - ball.position) > 0.0 or ball_flat.distance_to(actor.position) < Roles.SAVE_REACH
			if carrier == null and approaching and ball_flat.distance_to(actor.position) < 12.0 and actor.kick_cooldown <= 0.0 and actor.ai_save_wait < 0.0:
				actor.ai_save_wait = ai_delay(actor, "skill")
		elif not tactics.walls[actor.team].is_empty() and tactics.walls[actor.team].runner == actor:
			actor.target = tactics.support(actor)
		elif defensive_targets[actor.team].has(actor):
			actor.target = defensive_targets[actor.team][actor]
		elif (carrier == null or carrier.team != actor.team) and actor in chasers[actor.team]:
			var prediction := ball_flat + Vector3(ball.velocity.x, 0, ball.velocity.z) * 0.15
			actor.target = prediction
		else:
			actor.target = tactics.support(actor)
		_try_ai_ability(actor, actor in chasers[actor.team] or defensive_targets[actor.team].has(actor) or actor.goalkeeper)
		_avoid_warning(actor)


func chaser_count(team: int) -> int:
	# One player challenges; a second may recover a loose ball near our goal.
	return 2 if carrier == null and goal_threat(team, ball.position) > 0.6 else 1


func _add_player_coverage(targets: Dictionary, human: Node3D = null) -> void:
	if human == null:
		human = player
	if difficulty != Settings.Difficulty.HARD or not human.human or human.goalkeeper or carrier == null or carrier.team != human.team:
		return
	# React to current positions and observed velocity, never mouse input.
	if human.position.x * (1.0 if human.team == 0 else -1.0) < -10.0:
		return
	var candidates: Array = players.filter(func(a): return a.team != human.team and not a.human and not a.goalkeeper and not targets.has(a) and a.position.distance_to(human.position) < 24.0)
	if candidates.is_empty():
		return
	candidates.sort_custom(func(a, b): return a.position.distance_squared_to(human.position) < b.position.distance_squared_to(human.position))
	var defender = candidates[0]
	var point: Vector3 = human.position + human.velocity * 0.25
	if carrier == human:
		# Second angle covers the advancing player's nearest passing option.
		var receiver := _pass_target(human)
		if receiver != null:
			point = human.position.lerp(receiver.position, 0.35)
	else:
		point = human.position.lerp(carrier.position, 0.18)
	targets[defender] = defender.constrain_position(point)


func goal_threat(team: int, point: Vector3) -> float:
	var own_goal := Vector3(-48.0 if team == 0 else 48.0, 0, 0)
	return clampf((42.0 - own_goal.distance_to(point)) / 34.0, 0.0, 1.0)


func _defensive_targets(team: int, ball_flat: Vector3) -> Dictionary:
	var targets := {}
	if carrier != null and carrier.team == team:
		return targets
	if carrier == null and not tactics.flight.is_empty() and tactics.flight.from.team == team:
		return targets
	var own_goal := Vector3(-48.0 if team == 0 else 48.0, 0, 0)
	var defenders: Array = players.filter(func(a): return a.team == team and not a.human and not a.goalkeeper and not a.action_blocked())
	if defenders.is_empty():
		return targets
	defenders.sort_custom(func(a, b): return a.position.distance_squared_to(ball_flat) < b.position.distance_squared_to(ball_flat))
	var threat := goal_threat(team, ball_flat)
	var goal_side := (own_goal - ball_flat).normalized()
	var movement: Vector3 = carrier.velocity if carrier != null else Vector3(ball.velocity.x, 0, ball.velocity.z)
	var prediction := ball_flat + movement * 0.16
	var presser = defenders[0]
	targets[presser] = presser.constrain_position(prediction + goal_side * lerpf(1.6, 0.35, threat))
	# A covering player protects the pass/shot lane instead of joining the tackle.
	var cover: Array = defenders.filter(func(a): return a != presser and a.tactical_line != Formations.Line.FRONT)
	if threat > 0.35 and not cover.is_empty():
		var point := prediction + goal_side * 7.0
		cover.sort_custom(func(a, b): return a.position.distance_squared_to(point) < b.position.distance_squared_to(point))
		targets[cover[0]] = cover[0].constrain_position(point)
	# Assign distinct receivers to the remaining backs, midfielders and forwards.
	var attackers: Array = players.filter(func(a): return a.team != team and not a.goalkeeper and a != carrier)
	attackers.sort_custom(func(a, b): return _mark_priority(a, own_goal) < _mark_priority(b, own_goal))
	for attacker in attackers:
		if players.any(func(a): return a.team == team and a.human and a.position.distance_to(attacker.position) < 2.2):
			continue
		var available: Array = defenders.filter(func(a): return not targets.has(a) and a.position.distance_to(attacker.position) < 30.0)
		if available.is_empty():
			continue
		available.sort_custom(func(a, b): return a.position.distance_to(attacker.position) + absf(a.home.x - attacker.position.x) * 0.18 < b.position.distance_to(attacker.position) + absf(b.home.x - attacker.position.x) * 0.18)
		var defender = available[0]
		var gap := lerpf(3.0, 1.1, goal_threat(team, attacker.position))
		targets[defender] = defender.constrain_position(attacker.position + (own_goal - attacker.position).normalized() * gap)
	return targets


func _mark_priority(actor: Node3D, own_goal: Vector3) -> float:
	return actor.position.distance_to(own_goal) - (5.0 if actor.tactical_line == Formations.Line.FRONT else 0.0)


func _ai_domain_target(actor: Node3D) -> Variant:
	if carrier == null or carrier.team == actor.team:
		return null
	var threats: Array = players.filter(func(a): return a.team != actor.team and not a.goalkeeper and goal_threat(actor.team, a.position) > 0.15)
	threats.sort_custom(func(a, b): return (0 if a == carrier else 1) < (0 if b == carrier else 1))
	for opponent in threats:
		var point := field_point(actor, opponent.position + opponent.velocity * 0.25, actor.domain_range())
		if point.distance_to(opponent.position) > actor.domain_radius() * 0.75:
			continue
		# Rechecked at the cast itself, so two pending teammates cannot stack fields.
		if fields.any(func(field): return field.team == actor.team and field.remaining > 1.0 and field.position.distance_to(point) < (field.radius + actor.domain_radius()) * 0.85):
			continue
		return point
	return null


func _try_ai_ability(actor: Node3D, contesting: bool) -> void:
	actor.ai_contesting = contesting
	if not _ai_wants_ability(actor, contesting):
		actor.ai_skill_pending = false
		return
	if not actor.ai_skill_pending:
		actor.ai_skill_pending = true
		actor.ai_skill_wait = ai_delay(actor, "skill")


func _ai_wants_ability(actor: Node3D, contesting: bool) -> bool:
	if not actor.w_unlocked:
		return false
	if actor.ability_cooldown > 0 or actor.charging or actor.dash_remaining > 0 or actor.ai_kick_power > 0 or actor.action_blocked():
		return false
	var distance: float = actor.position.distance_to(ball.position)
	var offset: Vector3 = actor.target - actor.position
	match actor.archetype:
		Roles.Kind.RUNNER:
			return contesting and offset.length() > 4.0 and distance < 22.0
		Roles.Kind.GUARD:
			if distance < 16.0:
				for opponent in players:
					if opponent.team != actor.team and actor.position.distance_to(opponent.position) < actor.slow_radius() * 0.9:
						return true
		Roles.Kind.CHARGER:
			return contesting and offset.length() > actor.max_dash_distance() and distance < 20.0
		Roles.Kind.STRIKER:
			return distance < 24.0 and _throw_target(actor) != null
		Roles.Kind.WARDEN:
			return _ai_domain_target(actor) != null
		Roles.Kind.KEEPER:
			for opponent in players:
				if opponent.team != actor.team and _in_keeper_cone(actor, opponent.position):
					return true
	return false


func _queue_ai_kick(actor: Node3D, direction: Vector3, power: float, error_degrees: float) -> void:
	actor.ai_aim_error = deg_to_rad(rng.randf_range(-error_degrees, error_degrees))
	actor.ai_aim_direction = direction.normalized().rotated(Vector3.UP, actor.ai_aim_error)
	actor.ai_kick_power = power
	actor.ai_skill_pending = false
	actor.target = actor.position


func _apply_slow_fields(delta: float = 0.0) -> void:
	for actor in players:
		actor.slow_multiplier = 1.0
	for source in players:
		if source.archetype not in [Roles.Kind.GUARD, Roles.Kind.KEEPER] or source.ability_time <= 0 or source.stun_time > 0:
			continue
		for opponent in players:
			var inside: bool = _in_keeper_cone(source, opponent.position) if source.archetype == Roles.Kind.KEEPER else source.position.distance_squared_to(opponent.position) <= source.slow_radius() * source.slow_radius()
			if opponent.team != source.team and inside and opponent.e_immunity_time <= 0.0:
				# Overlapping fields apply the configured slow once.
				var multiplier: float = Roles.KEEPER_SLOW_MULTIPLIER if source.archetype == Roles.Kind.KEEPER else Roles.SLOW_MULTIPLIER
				opponent.slow_multiplier = minf(opponent.slow_multiplier, 1.0 - (1.0 - multiplier) * (1.0 - opponent.slow_resistance()))

	for field in fields:
		for opponent in players:
			if opponent.team != field.team and opponent.e_immunity_time <= 0.0 and opponent.position.distance_squared_to(field.position) <= field.radius * field.radius:
				opponent.slow_multiplier = minf(opponent.slow_multiplier, 1.0 - (1.0 - field.multiplier) * (1.0 - opponent.slow_resistance()))
				if field.title == "镇守领域":
					field.source.stats.domain_slow_seconds += delta


func _pass_target(actor: Node3D) -> Node3D:
	return tactics.pass_target(actor)


func _try_tackle(delta: float) -> void:
	var tackler: Node3D = null
	for actor in players:
		var in_range := false
		if carrier != null and possession_lock <= 0.0 and actor.team != carrier.team and not actor.action_blocked():
			var reach: float = 1.4 * actor.hit_scale() + carrier.collision_radius() - 0.51
			in_range = actor.position.distance_to(carrier.position) < reach
		if not in_range:
			actor.ai_tackle_target = null
			actor.ai_tackle_wait = 0.0
			continue
		if not actor.human:
			if actor.ai_tackle_target != carrier:
				actor.ai_tackle_target = carrier
				actor.ai_tackle_wait = ai_delay(actor, "tackle")
			else:
				actor.ai_tackle_wait = maxf(0.0, actor.ai_tackle_wait - delta)
			if actor.ai_tackle_wait > 0.0:
				continue
		if tackler == null:
			tackler = actor
	if tackler != null:
		tackler.stats.tackles += 1
		_defense_income(tackler, Gear.TACKLE_GOLD, "成功抢断")
		carrier.stats.turnovers += 1
		carrier = tackler
		carrier.decision_time = 0.6
		tactics.on_control(carrier)
		possession_lock = 0.9 + carrier.equipment_bonus("protection")
		for actor in players:
			actor.ai_tackle_target = null
			actor.ai_tackle_wait = 0.0


func _update_possession(delta: float) -> void:
	_try_tackle(delta)
	if carrier != null:
		var at: Vector3 = carrier.position + carrier.facing * carrier.control_distance()
		last_touch = carrier
		at.y = Ball.RADIUS + absf(sin(carrier.gait)) * 0.035
		ball.velocity = (at - ball.position) / delta
		ball.position = at
		ball.update_visual(delta)
	else:
		ball.step(delta)
		# Resolve a ball that has already crossed a boundary before anyone can claim a catch.
		if absf(ball.position.x) > Stadium.HALF_LENGTH + Ball.RADIUS or absf(ball.position.z) > Stadium.HALF_WIDTH - Ball.RADIUS:
			return
		if possession_lock > 0:
			return
		var flat_ball := Vector3(ball.position.x, 0, ball.position.z)
		var closest: Node3D = null
		var closest_distance := INF
		for actor in players:
			if actor.action_blocked():
				continue
			if actor.goalkeeper and actor == last_touch and actor.kick_cooldown > 0.0:
				continue # Do not re-catch our own distribution inside equipment-expanded pickup reach.
			var distance: float = actor.position.distance_to(flat_ball)
			var reach: float = (1.65 if actor.goalkeeper else 1.2) * actor.hit_scale() * (1.0 + actor.equipment_bonus("pickup"))
			var height: float = (2.6 if actor.goalkeeper else 1.0) * actor.hit_scale()
			if actor.archetype == Roles.Kind.KEEPER and actor.save_time > 0:
				reach = Roles.SAVE_REACH * actor.hit_scale() * (1.0 + actor.equipment_bonus("pickup"))
				height = Roles.SAVE_HEIGHT * actor.hit_scale()
			if distance < reach and ball.position.y < height and distance < closest_distance:
				closest = actor
				closest_distance = distance
		if closest != null:
			var previous_touch: Node3D = last_touch
			last_touch = closest
			var hand_save: bool = closest.archetype == Roles.Kind.KEEPER and closest.save_time > 0.0
			if ball.velocity.length() < 19.0 or hand_save or tactics.can_trap(closest):
				var saved: bool = closest.goalkeeper and previous_touch.team != closest.team and ball.velocity.length() > 5.0
				if saved:
					closest.stats.saves += 1
				closest.stats.recoveries += 1
				if previous_touch.team != closest.team:
					closest.stats.interceptions += 1
					_defense_income(closest, Gear.INTERCEPT_GOLD, "拦截来球")
				carrier = closest
				carrier.decision_time = 0.55
				tactics.on_control(carrier, saved)
				possession_lock = 0.65 + carrier.equipment_bonus("protection")
			else:
				if tactics.cushion(closest):
					return
				tactics.end_flight("rebound", closest)
				var rebound: Vector3 = (flat_ball - closest.position).normalized()
				ball.velocity = rebound * 9.0 + Vector3.UP * 2.0
				possession_lock = 0.2


func _check_boundaries() -> void:
	# The full ball must cross the line. Sidelines rebound for this arcade demo.
	if absf(ball.position.x) > Stadium.HALF_LENGTH + Ball.RADIUS:
		if absf(ball.position.z) < Stadium.GOAL_HALF_WIDTH - Ball.RADIUS and ball.position.y < Stadium.GOAL_HEIGHT - Ball.RADIUS:
			var scoring_team := 0 if ball.position.x > 0 else 1
			var own_goal: bool = last_touch.team != scoring_team
			var reward_multiplier := 1.0 if own_goal else comeback_multiplier(scoring_team)
			score[scoring_team] += 1
			goal_scored.emit(scoring_team)
			if not own_goal:
				last_touch.stats.goals += 1
				award_money(last_touch, roundi(Gear.GOAL_GOLD * reward_multiplier), "落后进球赏金" if reward_multiplier > 1.0 else "进球")
			else:
				last_touch.stats.own_goals += 1
			goal_events.append({
				"time": snappedf(match_elapsed(), 0.1),
				"team": scoring_team, "role": last_touch.archetype,
				"shirt_number": last_touch.shirt_number,
				"own_goal": own_goal, "reward_multiplier": reward_multiplier
			})
			tactics.end_keeper_hold("goal")
			for actor in players:
				if actor.team == scoring_team:
					award_money(actor, roundi(Gear.TEAM_GOAL_GOLD * reward_multiplier), "球队进球")
			if is_practice():
				practice.reset_field()
				announce("进球！继续练习", 2.0)
				return
			if mode == "rogue":
				if overtime_count > 0 or score[0] - score[1] >= 3:
					finish_session(score[0] > score[1])
				else:
					reset_kickoff(1 - scoring_team)
					goal_pause = 1.8
					announce("蓝队进球！" if scoring_team == 0 else "珊瑚队进球！", 3.0)
				return
			reset_kickoff(1 - scoring_team)
			goal_pause = 1.8
			announce("蓝队进球！" if scoring_team == 0 else "珊瑚队进球！", 2.6)
			if not simulation_mode and not agent_controlled:
				whistle_sound.play()
			return
		ball.position.x = signf(ball.position.x) * (Stadium.HALF_LENGTH - Ball.RADIUS)
		tactics.end_keeper_hold("boundary")
		ball.velocity.x *= -0.65
		carrier = null
		possession_lock = 0.2
	if absf(ball.position.z) > Stadium.HALF_WIDTH - Ball.RADIUS:
		tactics.end_keeper_hold("boundary")
		ball.position.z = signf(ball.position.z) * (Stadium.HALF_WIDTH - Ball.RADIUS)
		ball.velocity.z *= -0.65
		carrier = null
		possession_lock = 0.2


func _process(delta: float) -> void:
	if simulation_mode:
		return
	_update_camera(delta)
	marker_time = maxf(0.0, marker_time - delta)
	marker.visible = marker_time > 0 and is_playing()
	marker.scale = Vector3.ONE * (0.8 + marker_time * 0.5)
	if tutorial_marker != null:
		tutorial_marker.visible = practice != null and practice.step in [0, 1, 3, 4] and is_playing()
		if tutorial_marker.visible:
			tutorial_marker.position = practice.waypoint + Vector3.UP * 0.1
	hud.queue_redraw()


func _update_camera(delta: float) -> void:
	var focus := camera_focus
	if overview:
		focus = Vector3.ZERO
	elif player != null and (camera_locked or Input.is_physical_key_pressed(KEY_SPACE)):
		focus = player.position + (ball.position - player.position) * 0.12 if ball != null else player.position
		focus.x = clampf(focus.x, -32, 32)
		focus.z = clampf(focus.z, -16, 16)
	elif started and not paused:
		var mouse := get_viewport().get_mouse_position()
		var rect := get_viewport().get_visible_rect().size
		var pan := Vector2.ZERO
		if mouse.x >= 0 and mouse.x <= rect.x and mouse.y >= 0 and mouse.y <= rect.y:
			pan.x = -1.0 if mouse.x < 15 else (1.0 if mouse.x > rect.x - 15 else 0.0)
			pan.y = -1.0 if mouse.y < 15 else (1.0 if mouse.y > rect.y - 15 else 0.0)
		focus += Vector3(pan.x + pan.y * 0.25, 0, pan.y - pan.x * 0.25) * delta * 28.0
		focus.x = clampf(focus.x, -48, 48)
		focus.z = clampf(focus.z, -30, 30)
	focus.y = 0
	camera_focus = camera_focus.lerp(focus, minf(1, delta * 7.0))
	camera.position = camera_focus + Vector3(13, 43, 36)
	camera.look_at(camera_focus)
	camera.size = lerpf(camera.size, 78.0 if overview else zoom_size, minf(1, delta * 8.0))


func announce(message: String, duration: float) -> void:
	announcement = message
	announcement_time = duration


func _make_audio() -> void:
	kick_sound = AudioStreamPlayer.new()
	whistle_sound = AudioStreamPlayer.new()
	add_child(kick_sound)
	add_child(whistle_sound)
	kick_sound.stream = _tone(false)
	kick_sound.volume_db = -10
	whistle_sound.stream = _tone(true)
	whistle_sound.volume_db = -21


func _tone(whistle: bool) -> AudioStreamWAV:
	var audio := AudioStreamWAV.new()
	audio.format = AudioStreamWAV.FORMAT_16_BITS
	audio.mix_rate = 22050
	var duration := 0.38 if whistle else 0.12
	var samples := int(audio.mix_rate * duration)
	var data := PackedByteArray()
	data.resize(samples * 2)
	for i in range(samples):
		var t := float(i) / audio.mix_rate
		var envelope := sin(PI * float(i) / samples)
		var value: float
		if whistle:
			value = sin(TAU * 2350 * t + sin(TAU * 26 * t) * 0.8) * envelope
		else:
			value = (sin(TAU * (115 - t * 380) * t) * 0.7 + sin(i * 12.9898) * 0.3) * exp(-t * 35)
		data.encode_s16(i * 2, int(value * 21000))
	audio.data = data
	return audio
