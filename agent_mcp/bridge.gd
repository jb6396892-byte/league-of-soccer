extends SceneTree
## Private local transport for server.py. Gameplay still runs in the real Match.
const Shell = preload("res://scripts/game_shell.gd")
const Roles = preload("res://scripts/archetypes.gd")
const Gear = preload("res://scripts/equipment.gd")
const ES = preload("res://scripts/purchasable_skills.gd")
const Modes = preload("res://scripts/game_modes.gd")
const Run = preload("res://scripts/rogue_run.gd")
const Forms = preload("res://scripts/formations.gd")
const Settings = preload("res://scripts/match_settings.gd")
const Practice = preload("res://scripts/practice.gd")
const AnnotationHUD = preload("res://agent_mcp/annotation_hud.gd")
const Stadium = preload("res://scripts/stadium.gd")
const DT := 1.0 / 60.0
var shell: Node
var peer := StreamPeerTCP.new()
var buffer := ""
var session_dir := ""
var ready_sent := false
var busy := false
var evaluation_access := false
var frames := 0
var match_id := 0
var match_seed := 0
var annotations_enabled := true


func _initialize() -> void:
	_boot.call_deferred()


func _boot() -> void:
	var options := {}
	for arg in OS.get_cmdline_user_args():
		if arg.contains("="):
			options[arg.get_slice("=", 0)] = arg.substr(arg.find("=") + 1)
	session_dir = options["--session-dir"]
	evaluation_access = options.get("--evaluation-access", "false") == "true"
	shell = Shell.new()
	shell.agent_controlled = true
	shell.progress_path = session_dir.path_join("progress.cfg")
	shell.rogue_path = session_dir.path_join("rogue-checkpoint.cfg")
	root.add_child(shell)
	shell.set_process_input(false)
	if evaluation_access:
		for rules in Modes.CHALLENGES:
			shell.cleared.append(rules.id)
		shell.rogue_cleared = Run.MAX_ASCENSION - 1
	AudioServer.set_bus_mute(0, true)
	var error := peer.connect_to_host("127.0.0.1", int(options["--port"]))
	if error != OK:
		push_error("Agent bridge connection failed: %s" % error)
		quit(1)


func _process(_delta: float) -> bool:
	if shell == null or busy:
		return false
	peer.poll()
	if peer.get_status() == StreamPeerTCP.STATUS_CONNECTED:
		if not ready_sent:
			_send({"hello": "soccer-agent-v1", "token": OS.get_environment("SOCCER_AGENT_TOKEN")})
			OS.unset_environment("SOCCER_AGENT_TOKEN")
			ready_sent = true
			print("Agent bridge connected; fixed-step control ready.")
		if peer.get_available_bytes() > 0:
			buffer += peer.get_utf8_string(peer.get_available_bytes())
		if buffer.contains("\n"):
			var end := buffer.find("\n")
			var request = JSON.parse_string(buffer.substr(0, end))
			buffer = buffer.substr(end + 1)
			busy = true
			_handle(request)
	elif ready_sent or peer.get_status() == StreamPeerTCP.STATUS_ERROR:
		busy = true
		_shutdown()
	return false


func _shutdown() -> void:
	shell.leave_session()
	quit()


func _send(data: Dictionary) -> void:
	peer.put_data((JSON.stringify(data) + "\n").to_utf8_buffer())


func _handle(request: Dictionary) -> void:
	var result: Dictionary
	if request.method == "screenshot":
		if DisplayServer.get_name() == "headless":
			result = fail("Headless sessions cannot render screenshots. Launch with headless=false.")
		else:
			await process_frame
			await RenderingServer.frame_post_draw
			var path := session_dir.path_join(request.params.filename)
			var error := root.get_texture().get_image().save_png(path)
			result = {"path": path, "state": observe(false)} if error == OK else fail("Screenshot write failed: %s" % error)
	else:
		result = dispatch(request.method, request.get("params", {}))
	freeze_game()
	_send({"id": request.id, "result": result})
	busy = false


func fail(message: String) -> Dictionary:
	return {"error": message}


func freeze_game() -> void:
	if shell.game != null:
		if shell.game.hud.get_script() != AnnotationHUD:
			var old_hud = shell.game.hud
			var patch := AnnotationHUD.new()
			patch.game = shell.game
			patch.shop_tab = old_hud.shop_tab
			patch.annotations_enabled = annotations_enabled
			old_hud.get_parent().add_child(patch)
			old_hud.free()
			shell.game.hud = patch
		shell.game.agent_controlled = true
		shell.game.set_physics_process(false)
		shell.game.set_process_unhandled_input(false)


func dispatch(method: String, p: Dictionary) -> Dictionary:
	match method:
		"observe": return observe(p.get("detailed", false))
		"catalog": return catalog(p.section)
		"start": return start_match(p)
		"act": return act(p)
		"shop": return shop(p)
		"menu": return menu_action(p)
		"view":
			if shell.game == null: return fail("Start a match first.")
			annotations_enabled = p.annotations
			shell.game.hud.annotations_enabled = annotations_enabled
			shell.game.overview = p.camera == "overview"
			shell.game.camera_locked = true
			shell.game.help_visible = p.help
			shell.game.hud.shop_tab = p.shop_tab
			shell.game._update_camera(1.0)
			return observe(false)
	return fail("Unknown bridge method.")


func start_match(p: Dictionary) -> Dictionary:
	if p.mode == "conquest" and p.level - 1 > shell.unlocked_level():
		return fail("Level is locked. Complete earlier levels, or launch a new evaluation_access session.")
	if p.mode == "rogue" and p.ascension > shell.rogue_unlocked:
		return fail("Ascension is locked. Clear the preceding ascension, or use evaluation_access in a new session.")
	shell.leave_session()
	match_id += 1
	frames = 0
	match_seed = p.seed
	if p.mode == "rogue":
		shell.clear_rogue_checkpoint()
		shell.rogue_ascension = p.ascension
		shell.rogue = Run.new(p.line, p.seed, p.ascension)
		shell.launch_rogue_stage()
	else:
		shell.free_minutes = p.minutes
		shell.free_difficulty = p.difficulty
		shell.free_ally_difficulty = p.ally_difficulty
		shell.open_mode(p.mode, p.level - 1, p.hero, false)
		shell.game.rng.seed = p.seed
		if not shell.game.started:
			shell.game.team_formations[0] = p.formation
			shell.game.start_match()
		if p.mode == "conquest":
			match_seed = Modes.CHALLENGES[p.level - 1].seed
	freeze_game()
	return observe(false)


func act(p: Dictionary) -> Dictionary:
	var g = shell.game
	if g == null or shell.page != "session" or g.finished:
		return fail("No active match. Use soccer_start_match or choose a reward.")
	if g.shop_open:
		return fail("Shop is waiting. Buy/equip items, then soccer_shop(action='continue').")
	var has_input: bool = p.move != null or p.aim != null or p.q or p.w != "none" or p.e
	if not g.is_playing() and has_input:
		return fail("Kickoff countdown: call soccer_act with only seconds to advance it first.")
	var a = g.player
	var actions := {}
	var point: Variant = vec(p.aim) if p.aim != null else null
	if point != null:
		var direction: Vector3 = point - a.position
		var accepted: bool = not a.action_blocked() and direction.length() > 0.2
		if accepted:
			a.target = a.position
			a.velocity = Vector3.ZERO
			a.facing = direction.normalized()
		actions.aim = accepted
	if p.move != null:
		a.target = a.constrain_position(vec(p.move))
		actions.move = true
	if p.q:
		var before: float = a.kick_cooldown
		g.player_kick()
		var accepted: bool = a.kick_cooldown > before
		actions.q = {"accepted": accepted, "reason": "" if accepted else "Q requires range, available cooldown and no blocking action."}
	if p.w != "none":
		var accepted: bool = g.release_ability(a) if p.w == "release" else g.use_ability(a, a.facing, point)
		actions.w = {"accepted": accepted, "reason": "" if accepted else "W requires learning/cooldown/action readiness; 镇域 needs aim; 月影 uses press then release."}
	if p.e:
		var reason: String = g.e_use_error(a)
		actions.e = {"accepted": g.use_e(a, point), "reason": reason}
	var requested_frames := maxi(1, roundi(p.seconds * 60.0))
	var advanced := 0
	var goals_before: int = g.goal_events.size()
	var lesson_before: int = g.practice.step if g.mode == "tutorial" else -1
	var stop_reason := "duration"
	for i in range(requested_frames):
		g._physics_process(DT)
		advanced += 1
		frames += 1
		if g.finished:
			stop_reason = "result"
			break
		if g.shop_open:
			stop_reason = "shop"
			break
		if g.goal_events.size() != goals_before:
			stop_reason = "goal"
			break
		if g.mode == "tutorial" and g.practice.step != lesson_before:
			stop_reason = "lesson"
			break
	return {"actions": actions, "advanced_seconds": advanced * DT, "stop_reason": stop_reason, "state": observe(false)}


func shop(p: Dictionary) -> Dictionary:
	var g = shell.game
	if g == null or not g.shop_open or g.finished:
		return fail("Shop is not open. Free/conquest: use soccer_menu(action='timeout') while your team has possession and a token. Training/tutorial: use soccer_menu(action='practice_shop').")
	var accepted := false
	var reason := ""
	match p.action:
		"continue":
			g.skip_shop()
			accepted = true
		"buy_item":
			reason = g.purchase_error(g.player, p.id)
			accepted = g.buy_item(g.player, p.id)
		"sell_item": accepted = g.sell_item(g.player, p.id)
		"buy_e":
			reason = g.e_purchase_error(g.player, p.id)
			accepted = g.buy_e(g.player, p.id)
		"equip_e": accepted = g.equip_e(g.player, p.id)
		"formation": accepted = g.choose_formation(p.id)
	if not accepted and reason.is_empty():
		reason = "Choice unavailable. Check item/slot ID, owned E charges, and mode rules."
	return {"accepted": accepted, "reason": reason, "state": observe(false)}


func menu_action(p: Dictionary) -> Dictionary:
	match p.action:
		"timeout":
			if shell.game == null: return fail("Start a match first.")
			var reason: String = shell.game.timeout_error(shell.game.player.team)
			var accepted: bool = shell.game.request_timeout(shell.game.player.team)
			return {"accepted": accepted, "reason": reason, "state": observe(false)}
		"home": shell.leave_session()
		"credits":
			shell.leave_session()
			shell.set_page("credits")
		"talent":
			if shell.page != "rogue_reward" or p.index >= shell.rogue.offers.size():
				return fail("No such reward choice. Observe the current offers and use its zero-based index.")
			var old_game = shell.game
			shell.activate("talent:%d" % p.index)
			if shell.game != old_game:
				match_id += 1
				frames = 0
		"resume_checkpoint":
			if shell.rogue_checkpoint.is_empty(): return fail("No checkpoint in this isolated session.")
			shell.resume_rogue()
			match_id += 1
			frames = 0
		"practice_shop":
			if shell.game == null or not shell.game.is_practice() or shell.game.finished:
				return fail("Practice shop is available only in training/tutorial.")
			shell.activate("shop")
		"give_ball", "reset_field", "refill", "serve_shot":
			if shell.game == null or shell.game.mode != "training":
				return fail("Practice aids are restricted to training; no match-state cheats are exposed.")
			if p.action == "serve_shot" and not shell.game.player.goalkeeper:
				return fail("serve_shot requires the keeper hero in training.")
			shell.game.practice.call(p.action)
	freeze_game()
	return observe(false)


func vec(value: Array) -> Vector3:
	return Vector3(value[0], 0, value[1])


func xy(value: Vector3) -> Array:
	return [snappedf(value.x, 0.001), snappedf(value.z, 0.001)]


func actor_id(actor: Node3D) -> String:
	return "" if actor == null else "%s:%d" % ["blue" if actor.team == 0 else "red", actor.shirt_number]


func actor_state(a: Node3D, detailed: bool) -> Dictionary:
	var result := {"id": actor_id(a), "hero": a.archetype, "name": Roles.NAMES[a.archetype],
		"line": Forms.LINE_NAMES[a.tactical_line], "position": xy(a.position), "velocity": xy(a.velocity),
		"facing": xy(a.facing), "human": a.human, "stun_seconds": a.stun_time}
	if detailed:
		result.merge({"move_target": xy(a.target), "speed": a.move_speed(), "gold": a.gold,
			"inventory": a.inventory, "q_cooldown": a.kick_cooldown, "w_cooldown": a.ability_cooldown,
			"w_unlocked": a.w_unlocked, "charging": a.charging, "charge_fraction": a.charge_fraction(),
			"e_selected": a.e_selected, "e_charges": a.e_charges, "e_unlimited": a.e_unlimited,
			"e_cooldown": a.e_cooldown, "stats": a.stats, "bonuses": a.extra_bonuses})
	return result


func observe(detailed: bool) -> Dictionary:
	freeze_game()
	var result := {"page": shell.page, "waiting_for_agent": true, "match_id": match_id,
		"physics_frames": frames, "evaluation_access": evaluation_access,
		"progress": {"conquest_unlocked_through": shell.unlocked_level() + 1,
			"rogue_unlocked_through": shell.rogue_unlocked, "tutorial_done": shell.tutorial_done,
			"checkpoint_available": not shell.rogue_checkpoint.is_empty()}}
	var g = shell.game
	if g == null: return result
	result.merge({"mode": g.mode, "seed": match_seed, "phase": "result" if g.finished else ("shop" if g.shop_open else ("kickoff" if g.goal_pause > 0 else "playing")),
		"annotations": annotations_enabled,
		"timeout": {"tokens": g.timeout_tokens, "next_in": Gear.SUPPLY_SECONDS - g.supply_clock, "requested_by": g.timeout_team, "blocked": g.timeout_error(g.player.team)},
		"score": g.score, "time_left": g.time_left, "elapsed": g.match_elapsed(),
		"overtime": g.overtime_count, "kickoff_team": g.kickoff_team, "countdown": g.goal_pause,
		"difficulty": Settings.NAMES[g.difficulty], "result_won": g.result_won if g.finished else null,
		"ally_difficulty": Settings.NAMES[g.ai_difficulty(g.player.team)],
		"player": actor_state(g.player, true), "players": [],
		"ball": {"position": xy(g.ball.position), "height": g.ball.position.y, "velocity": xy(g.ball.velocity), "vertical_velocity": g.ball.velocity.y,
			"carrier": actor_id(g.carrier), "last_touch": actor_id(g.last_touch)},
		"formations": [Forms.NAMES[g.team_formations[0]], Forms.NAMES[g.team_formations[1]]],
		"goals": g.goal_events, "fields": [], "projectiles": []})
	for a in g.players:
		result.players.append(actor_state(a, detailed))
	for field in g.fields:
		result.fields.append({"position": xy(field.position), "team": field.team, "radius": field.radius, "remaining": field.remaining})
	for shot in g.projectiles:
		result.projectiles.append({"position": xy(shot.position), "direction": xy(shot.direction), "remaining": shot.remaining})
	if g.shop_open:
		result.shop = {"title": g.shop_title, "items": [], "e_skills": [], "equipment_slots": Gear.SLOTS}
		for id in Gear.visible_items(g.player.archetype):
			result.shop.items.append({"id": id, "name": Gear.ITEMS[id].name, "price_now": Gear.buy_cost(g.player.inventory, id), "blocked": g.purchase_error(g.player, id)})
		for id in ES.visible_skills(g.player.archetype):
			result.shop.e_skills.append({"id": id, "name": ES.SKILLS[id].name, "cost": ES.SKILLS[id].cost, "blocked": g.e_purchase_error(g.player, id)})
	if g.mode == "tutorial" and g.practice.step < Practice.LESSONS.size():
		result.lesson = {"index": g.practice.step, "title": Practice.LESSONS[g.practice.step][0], "instructions": Practice.LESSONS[g.practice.step][1], "waypoint": xy(g.practice.waypoint)}
	if g.mode == "conquest":
		result.challenge = Modes.CHALLENGES[g.challenge_id]
	if g.mode == "rogue":
		result.rogue = {"stage": shell.rogue.stage, "ascension": shell.rogue.ascension, "build": shell.rogue.build_lines(),
			"checkpoint_choice": shell.rogue.checkpoint_choice, "curses": shell.rogue.curses, "offers": shell.rogue.offers}
	if detailed:
		result.purchases = g.purchase_events
		result.e_purchases = g.e_purchase_events
		result.e_casts = g.e_cast_events
	return result


func catalog(section: String) -> Dictionary:
	match section:
		"heroes":
			var heroes := []
			for id in range(Roles.NAMES.size()):
				heroes.append({"id": id, "name": Roles.NAMES[id], "passive": Roles.PASSIVES[id], "w": Roles.W_NAMES[id], "detail": Roles.W_DETAILS[id], "line": Forms.LINE_NAMES[Forms.PREFERRED_LINE[id]]})
			return {"heroes": heroes, "q": "Face a target then kick; keeper Q saves when not carrying. 月影 W: press, advance, release."}
		"equipment": return {"items": Gear.ITEMS, "id_rule": "Zero-based array index", "slots": Gear.SLOTS, "start_gold": Gear.START_GOLD, "supply_seconds": Gear.SUPPLY_SECONDS, "team_upgrade_cap": Gear.TEAM_UPGRADE_CAP}
		"e_skills": return {"skills": ES.SKILLS, "id_rule": "Zero-based array index; one equipped skill, charges stored separately."}
		"modes": return {"modes": ["free", "conquest", "tutorial", "training", "rogue"], "challenges": Modes.CHALLENGES, "level_rule": "One-based level argument", "formations": Forms.NAMES, "difficulties": Settings.NAMES, "lessons": Practice.LESSONS,
			"pitch": {"half_length": Stadium.HALF_LENGTH, "half_width": Stadium.HALF_WIDTH, "goal_half_width": Stadium.GOAL_HALF_WIDTH, "goal_height": Stadium.GOAL_HEIGHT}}
		"rogue": return {"stages": Run.STAGES, "checkpoints": Run.CHECKPOINTS, "qualities": Run.QUALITY_NAMES, "weights": Run.QUALITY_WEIGHTS, "scarce_weights": Run.SCARCE_WEIGHTS, "talents": Run.TALENTS, "crowns": Run.CROWNS, "ascensions": Run.ASCENSION_RULES,
			"learnable_w_hero_ids": range(Roles.NAMES.size()).filter(func(id): return id != Roles.Kind.KEEPER), "learnable_e_ids": range(Run.E_COOLDOWNS.size()), "rogue_e_cooldowns": Run.E_COOLDOWNS,
			"rules": "90 seconds; lead by 3 wins early; ties enter golden goal. Both teams hard AI. Start with player, 2 outfield teammates and a keeper."}
	return fail("Unknown catalog section.")
