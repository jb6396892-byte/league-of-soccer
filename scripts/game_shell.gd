extends Node
## Owns navigation and persistent progression; each mode gets a fresh match.
const MatchScene = preload("res://main.tscn")
const Menu = preload("res://scripts/main_menu.gd")
const Modes = preload("res://scripts/game_modes.gd")
const RogueRun = preload("res://scripts/rogue_run.gd")
var net: Node
var online_menu: Control
var rogue: RefCounted
var game: Node3D
var menu: Control
var page := "home"
var cleared: Array[String] = []
var completed: int:
	get:
		return cleared.size()
var tutorial_done := false
var progress_path := "user://conquest.cfg"
var rogue_path := "user://rogue-checkpoint.cfg"
var rogue_checkpoint: Dictionary = {}
var rogue_ascension := 0
var rogue_cleared := -1
var rogue_unlocked: int:
	get:
		return mini(RogueRun.MAX_ASCENSION, rogue_cleared + 1)
var notice := ""
var simulation_mode := false
var agent_controlled := false
var audio: Node
var last_mode := "free"
var last_level := 0
var free_minutes := 5
var free_difficulty := 1
var free_ally_difficulty := 1
var last_role := 0


func _ready() -> void:
	audio = preload("res://scripts/game_audio.gd").new()
	audio.enabled = not simulation_mode and not agent_controlled
	add_child(audio)
	load_progress()
	if simulation_mode:
		rogue_path = progress_path + ".rogue"
	load_rogue_checkpoint()
	var canvas := CanvasLayer.new()
	canvas.layer = 20
	add_child(canvas)
	menu = Menu.new()
	menu.shell = self
	canvas.add_child(menu)
	net = preload("res://scripts/net_session.gd").new()
	net.name = "Network"
	net.shell = self
	add_child(net)
	online_menu = preload("res://scripts/online_menu.gd").new()
	online_menu.shell = self
	canvas.add_child(online_menu)


func load_progress() -> void:
	if not FileAccess.file_exists(progress_path):
		return
	var config := ConfigFile.new()
	if config.load(progress_path) != OK:
		notice = "进度文件无法读取，本次从第一关开始。"
		return
	cleared.clear()
	var ids: Array = config.get_value("progress", "cleared", [])
	if not config.has_section_key("progress", "cleared"):
		ids = Modes.LEGACY_IDS.slice(0, clampi(int(config.get_value("progress", "completed", 0)), 0, Modes.LEGACY_IDS.size()))
	for rules in Modes.CHALLENGES:
		if rules.id in ids:
			cleared.append(rules.id)
	tutorial_done = bool(config.get_value("progress", "tutorial", false))
	rogue_cleared = clampi(int(config.get_value("rogue", "cleared_ascension", -1)), -1, RogueRun.MAX_ASCENSION)


func save_progress() -> void:
	var config := ConfigFile.new()
	config.set_value("progress", "cleared", cleared)
	config.set_value("progress", "tutorial", tutorial_done)
	config.set_value("rogue", "cleared_ascension", rogue_cleared)
	if config.save(progress_path) != OK:
		notice = "本次进度未能保存，请检查存储权限。"


func set_page(value: String) -> void:
	page = value
	if online_menu != null:
		online_menu.visible = page in ["online", "online_result"]
	if page == "conquest":
		menu.chapter = unlocked_level() / 5
	menu.focus_index = 0
	menu.queue_redraw()


func unlocked_level() -> int:
	var latest := 0
	for i in range(Modes.CHALLENGES.size()):
		if Modes.CHALLENGES[i].id in cleared:
			latest = maxi(latest, i + 1)
	return mini(latest, Modes.CHALLENGES.size() - 1)


func remember_settings() -> void:
	if game != null and game.mode != "rogue":
		last_role = game.selected_role
		if game.mode == "free":
			free_minutes = game.match_minutes
			free_difficulty = game.difficulty
			free_ally_difficulty = game.ally_difficulty


func leave_session() -> void:
	if net != null and net.active:
		net.close()
	remember_settings()
	if game != null:
		game.free()
		game = null
	rogue = null
	set_page("home")


func open_mode(value: String, level: int = 0, role: int = -1, immediate: bool = false) -> bool:
	if value == "conquest" and (level < 0 or level >= Modes.CHALLENGES.size() or level > unlocked_level()):
		return false
	remember_settings()
	if game != null:
		game.free()
	game = MatchScene.instantiate()
	game.simulation_mode = simulation_mode
	game.agent_controlled = agent_controlled
	game.mode = value
	game.challenge_id = level
	game.match_minutes = free_minutes
	game.difficulty = free_difficulty
	game.session_finished.connect(_finished)
	game.goal_scored.connect(audio.play_goal)
	game.ui_interaction.connect(audio.play_ui)
	add_child(game)
	if value == "free":
		game.choose_minutes(free_minutes)
		game.choose_ally_difficulty(free_ally_difficulty)
	var selected := last_role if role < 0 else role
	if value == "tutorial":
		selected = 0
	elif value == "conquest":
		game.difficulty = Modes.CHALLENGES[level].difficulty
		game.regulation_duration = Modes.CHALLENGES[level].seconds
		game.time_left = game.regulation_duration
		if Modes.CHALLENGES[level].role >= 0:
			selected = Modes.CHALLENGES[level].role
	game.choose_role(selected)
	last_mode = value
	last_level = level
	set_page("session")
	if value == "tutorial" or immediate:
		game.start_match()
	return true


func _finished(won: bool) -> void:
	if game.net != null:
		net.finish()
		return
	if game.mode == "rogue":
		if won and rogue.stage < RogueRun.STAGES:
			rogue.reward()
			set_page("rogue_reward")
		else:
			rogue.ended = true
			if won and rogue.stage == RogueRun.STAGES and rogue.ascension == rogue_unlocked and rogue.ascension > rogue_cleared:
				rogue_cleared = rogue.ascension
				save_progress()
			set_page("rogue_result")
		return
	if won and game.mode == "conquest":
		var id: String = Modes.CHALLENGES[game.challenge_id].id
		if id not in cleared:
			cleared.append(id)
		save_progress()
	elif won and game.mode == "tutorial":
		tutorial_done = true
		save_progress()
	set_page("result")


func start_rogue(line: int) -> void:
	if line not in [1, 2, 3] or rogue_ascension < 0 or rogue_ascension > rogue_unlocked:
		return
	remember_settings()
	clear_rogue_checkpoint()
	rogue = RogueRun.new(line, 0, rogue_ascension)
	launch_rogue_stage()


func load_rogue_checkpoint() -> void:
	if not FileAccess.file_exists(rogue_path):
		return
	var config := ConfigFile.new()
	if config.load(rogue_path) != OK:
		notice = "远征存档读取失败，原文件保留。"
		return
	var data = config.get_value("rogue", "checkpoint", {})
	var saved := RogueRun.new()
	if not data is Dictionary or not saved.restore(data):
		notice = "远征存档内容无效，原文件保留。"
		return
	rogue_checkpoint = saved.snapshot()


func save_rogue_checkpoint() -> void:
	rogue_checkpoint = rogue.checkpoint.duplicate(true)
	var config := ConfigFile.new()
	config.set_value("rogue", "checkpoint", rogue_checkpoint)
	var error := config.save(rogue_path + ".tmp")
	if error == OK:
		error = DirAccess.rename_absolute(rogue_path + ".tmp", rogue_path)
	if error != OK:
		notice = "存档写入失败：本次仍可回退，退出后无法保留新存档。"


func clear_rogue_checkpoint() -> void:
	rogue_checkpoint.clear()
	if FileAccess.file_exists(rogue_path):
		if DirAccess.remove_absolute(rogue_path) != OK:
			notice = "旧远征存档未能清除，请检查存储权限。"


func resume_rogue() -> void:
	if rogue_checkpoint.is_empty():
		return
	rogue = RogueRun.new()
	if rogue.restore(rogue_checkpoint):
		launch_rogue_stage()


func launch_rogue_stage() -> void:
	if game != null:
		game.free()
	game = MatchScene.instantiate()
	game.simulation_mode = simulation_mode
	game.agent_controlled = agent_controlled
	game.mode = "rogue"
	game.rogue = rogue
	game.session_finished.connect(_finished)
	game.goal_scored.connect(audio.play_goal)
	game.ui_interaction.connect(audio.play_ui)
	add_child(game)
	set_page("session")
	game.start_match()


func activate(action: String) -> void:
	audio.play_ui()
	if action.begins_with("ascension:") and page == "rogue_setup":
		rogue_ascension = clampi(int(action.get_slice(":", 1)), 0, RogueRun.MAX_ASCENSION)
		menu.queue_redraw()
		return
	if action.begins_with("rogue_start:") and page == "rogue_setup":
		start_rogue(int(action.get_slice(":", 1)))
		return
	if action.begins_with("talent:") and page == "rogue_reward":
		var saving: bool = rogue.checkpoint_choice
		if rogue.choose(int(action.get_slice(":", 1))):
			if rogue.awaiting_reward:
				set_page("rogue_reward")
			else:
				if saving:
					save_rogue_checkpoint()
				launch_rogue_stage()
		return
	if action.begins_with("chapter:"):
		menu.chapter = clampi(int(action.get_slice(":", 1)), 0, Modes.CHAPTERS.size() - 1)
		menu.focus_index = menu.chapter
		menu.queue_redraw()
		return
	if action.begins_with("level:"):
		open_mode("conquest", int(action.get_slice(":", 1)))
		return
	match action:
		"online":
			set_page("online")
			online_menu.refresh()
		"rogue_resume": resume_rogue()
		"rogue":
			leave_session()
			set_page("rogue_setup")
		"free", "training", "tutorial": open_mode(action)
		"conquest", "credits": set_page(action)
		"home": leave_session()
		"quit": get_tree().quit()
		"retry": open_mode(last_mode, last_level, -1, true)
		"next": open_mode("conquest", last_level + 1)
		"ball": game.practice.give_ball()
		"reset": game.practice.reset_field()
		"refill": game.practice.refill()
		"shot": game.practice.serve_shot()
		"shop":
			if game.shop_open:
				game.skip_shop()
			else:
				game.open_shop(0, "训练场 · 自由试装", true)


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_M:
		audio.toggle_mute()
		get_viewport().set_input_as_handled()
		return
	if page in ["online", "online_result"]:
		if event is InputEventKey and event.pressed and event.physical_keycode == KEY_ESCAPE:
			leave_session()
			get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseMotion:
		for i in range(menu.buttons.size()):
			if menu.buttons[i].enabled and menu.buttons[i].rect.has_point(event.position):
				if menu.focus_index != i:
					audio.play_ui("hover")
				menu.focus_index = i
				break
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var action: String = menu.action_at(event.position)
		if not action.is_empty():
			activate(action)
			get_viewport().set_input_as_handled()
			return
	if event is InputEventKey and event.pressed and not event.echo:
		if page != "session":
			if page == "conquest" and event.physical_keycode in [KEY_LEFT, KEY_RIGHT]:
				activate("chapter:%d" % (menu.chapter + (-1 if event.physical_keycode == KEY_LEFT else 1)))
			elif event.physical_keycode == KEY_ESCAPE:
				leave_session()
			elif event.physical_keycode in [KEY_UP, KEY_DOWN, KEY_TAB]:
				menu.move_focus(-1 if event.physical_keycode == KEY_UP or event.shift_pressed else 1)
				audio.play_ui("hover")
			elif event.physical_keycode in [KEY_ENTER, KEY_SPACE]:
				activate(menu.focus_action())
		elif game.mode == "training" and game.started and not game.paused:
			var keys := {KEY_F1: "ball", KEY_F2: "reset", KEY_F3: "refill", KEY_B: "shop"}
			if event.physical_keycode == KEY_F4 and game.player.goalkeeper:
				activate("shot")
			elif keys.has(event.physical_keycode):
				activate(keys[event.physical_keycode])
			elif event.physical_keycode >= KEY_1 and event.physical_keycode <= KEY_6:
				open_mode("training", 0, event.physical_keycode - KEY_1, true)
			else:
				return
		elif game.mode == "tutorial" and game.started and event.physical_keycode == KEY_B and not game.paused:
			activate("shop")
		else:
			return
		get_viewport().set_input_as_handled()
	elif page != "session":
		get_viewport().set_input_as_handled()


func _process(_delta: float) -> void:
	menu.queue_redraw()
