extends Node
## Two-player listen server. Only this node exposes RPCs; matches remain ordinary scenes.
const State = preload("res://scripts/network_state.gd")
const PROTOCOL := 3
const PORT := 24551
signal changed
var shell: Node
var active := false
var hosting := false
var phase := "offline"
var message := "创建房间，或输入房主 IP 加入。"
var members: Dictionary = {}
var options := {"minutes": 5, "difficulty": 1}
var local_name := "球员"
var actors: Dictionary = {}
var epoch := 0
var shop_round := 0
var shop_ready: Array[int] = []
var loaded: Array[int] = []
var move_sequence := 0
var move_ack := 0
var move_received: Dictionary = {}
var command_budget: Dictionary = {}
var elapsed := 0.0
var send_clock := 0.0
var input_clock := 0.0
var snapshot_id := 0
var received_id := -1
var local_menu := false
var last_event: Array = []
var fragment_id := -1
var fragments: Array[PackedByteArray] = []
var fragments_left := 0

func _ready() -> void:
	multiplayer.peer_connected.connect(_peer_connected)
	multiplayer.peer_disconnected.connect(_peer_disconnected)
	multiplayer.connected_to_server.connect(_connected)
	multiplayer.connection_failed.connect(func(): close("连接失败，请检查 IP、端口和房主是否已建房。"))
	multiplayer.server_disconnected.connect(func(): close("房主已离开或连接中断，房间已结束。"))

func host(player_name: String, port: int = PORT) -> void:
	if active:
		return
	var peer := ENetMultiplayerPeer.new()
	var error := peer.create_server(port, 1, 3)
	if error != OK:
		message = "建房失败（%d），请检查端口是否被占用。" % error
		changed.emit()
		return
	multiplayer.multiplayer_peer = peer
	active = true
	hosting = true
	phase = "lobby"
	local_name = player_name.strip_edges().left(20)
	members = {1: {"name": local_name, "team": 0, "role": 0, "ready": false}}
	message = "等待另一名玩家加入 · UDP %d" % port
	changed.emit()

func join(address: String, player_name: String, port: int = PORT) -> void:
	if active:
		return
	var peer := ENetMultiplayerPeer.new()
	var error := peer.create_client(address.strip_edges(), port, 3)
	if error != OK:
		message = "无法发起连接（%d），请检查地址。" % error
		changed.emit()
		return
	multiplayer.multiplayer_peer = peer
	active = true
	hosting = false
	phase = "connecting"
	elapsed = 0.0
	local_name = player_name.strip_edges().left(20)
	message = "正在连接……"
	changed.emit()

func close(reason: String = "已离开房间。") -> void:
	active = false
	phase = "offline"
	if multiplayer.multiplayer_peer is ENetMultiplayerPeer:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	members.clear()
	actors.clear()
	if shell.game != null and shell.game.net == self:
		shell.game.free()
		shell.game = null
	message = reason
	shell.set_page("online")
	changed.emit()

func _peer_connected(id: int) -> void:
	if hosting and phase != "lobby":
		multiplayer.multiplayer_peer.disconnect_peer(id)

func _connected() -> void:
	_register.rpc_id(1, PROTOCOL, local_name)

@rpc("any_peer", "call_remote", "reliable")
func _register(version: int, player_name: String) -> void:
	var id := multiplayer.get_remote_sender_id()
	if not hosting or phase != "lobby" or members.size() >= 2:
		return
	if version != PROTOCOL:
		_rejected.rpc_id(id, "游戏版本不同，请使用相同版本的联机包。")
		return
	members[id] = {"name": player_name.strip_edges().left(20), "team": 1, "role": 0, "ready": false}
	message = "双方选队、选角并准备后，由房主开赛。"
	_broadcast_room()

@rpc("authority", "call_remote", "reliable")
func _rejected(reason: String) -> void:
	close(reason)

func _peer_disconnected(id: int) -> void:
	if not hosting:
		return
	if actors.has(id) and shell.game != null:
		var actor = shell.game.players[actors[id]]
		actor.human = false
		actor.cancel_charge()
		actor.ai_think_wait = 0.0
		actor.ai_kick_power = 0.0
		actor.target = actor.position
		actors.erase(id)
		shell.game.announce("对方玩家已离线，由 NPC 接管", 5.0)
	members.erase(id)
	shop_ready.erase(id)
	message = "玩家已离开，等待重新加入。" if phase == "lobby" else "玩家已离线，由 NPC 接管。"
	_broadcast_room()
	if phase == "loading":
		_begin_play()
	elif phase == "playing" and shell.game.shop_open and shop_ready.size() == members.size():
		shell.game.skip_shop()

func _broadcast_room() -> void:
	if not multiplayer.get_peers().is_empty():
		_room.rpc(members, options, message)
	changed.emit()

@rpc("authority", "call_remote", "reliable")
func _room(roster: Dictionary, settings: Dictionary, notice: String) -> void:
	members = roster
	options = settings
	message = notice
	if phase == "connecting":
		phase = "lobby"
	changed.emit()

func select(team: int, role: int, ready: bool) -> void:
	if hosting:
		_select(1, team, role, ready)
	else:
		_pick.rpc_id(1, team, role, ready)

@rpc("any_peer", "call_remote", "reliable")
func _pick(team: int, role: int, ready: bool) -> void:
	if hosting:
		_select(multiplayer.get_remote_sender_id(), team, role, ready)

func _select(id: int, team: int, role: int, ready: bool) -> void:
	if phase != "lobby" or not members.has(id) or team not in [0, 1] or role < 0 or role > 5:
		return
	members[id].team = team
	members[id].role = role
	members[id].ready = ready
	_broadcast_room()

func configure(minutes: int, difficulty: int) -> void:
	if not hosting or phase != "lobby" or minutes < 5 or minutes > 15 or difficulty not in [0, 1, 2]:
		return
	options = {"minutes": minutes, "difficulty": difficulty}
	for member in members.values():
		member.ready = false
	_broadcast_room()

func can_start() -> bool:
	if not hosting or phase != "lobby" or members.size() != 2:
		return false
	var rows: Array = members.values()
	return rows.all(func(m): return m.ready) and not (rows[0].team == rows[1].team and rows[0].role == 4 and rows[1].role == 4)

func start() -> void:
	if can_start():
		epoch += 1
		_launch.rpc(epoch, members, options)

@rpc("authority", "call_local", "reliable")
func _launch(round_id: int, roster: Dictionary, settings: Dictionary) -> void:
	epoch = round_id
	members = roster
	options = settings
	phase = "loading"
	elapsed = 0.0
	last_event.clear()
	loaded.clear()
	actors.clear()
	move_received.clear()
	command_budget.clear()
	move_sequence = 0
	move_ack = 0
	received_id = -1
	fragment_id = -1
	local_menu = false
	if shell.game != null:
		shell.game.free()
	var game = shell.MatchScene.instantiate()
	shell.game = game
	game.net = self
	game.simulation_mode = shell.simulation_mode
	game.match_minutes = options.minutes
	game.difficulty = options.difficulty
	game.session_finished.connect(shell._finished)
	game.goal_scored.connect(shell.audio.play_goal)
	game.ui_interaction.connect(shell.audio.play_ui)
	shell.add_child(game)
	game.set_physics_process(false)
	for actor in game.players:
		actor.human = false
		actor.local_controlled = false
	var used: Array = []
	for id in members:
		var member: Dictionary = members[id]
		var shirt: int = 1 if member.role == 4 else 10
		var index: int = member.team * 11 + shirt - 1
		if index in used:
			index -= 1
		used.append(index)
		actors[id] = index
		var actor = game.players[index]
		actor.human = true
		actor.local_controlled = id == multiplayer.get_unique_id()
		actor.set_archetype(member.role)
		if actor.local_controlled:
			game.player = actor
			game.selected_role = member.role
			if actor.visuals_enabled:
				actor.selection.material_override = game.S.material(Color("#c9ff41"), true)
	game.start_match()
	shell.set_page("session")
	if hosting:
		loaded.append(1)
	else:
		_loaded.rpc_id(1, epoch)
	changed.emit()

@rpc("any_peer", "call_remote", "reliable")
func _loaded(round_id: int) -> void:
	var id := multiplayer.get_remote_sender_id()
	if hosting and phase == "loading" and round_id == epoch and members.has(id) and id not in loaded:
		loaded.append(id)
		if loaded.size() == members.size():
			_begin_play()

func _begin_play() -> void:
	_go.rpc(epoch, _snapshot())

@rpc("authority", "call_local", "reliable")
func _go(round_id: int, packet: Dictionary) -> void:
	if round_id != epoch:
		return
	phase = "playing"
	if not hosting:
		_accept(packet, true)
	shell.game.set_physics_process(hosting)
	changed.emit()

func shop_opened() -> void:
	if hosting:
		shop_round += 1
		shop_ready.clear()

func _snapshot() -> Dictionary:
	snapshot_id += 1
	return {"id": snapshot_id, "epoch": epoch, "state": State.capture(shell.game), "shop": shop_round, "ready": shop_ready.duplicate(), "ack": move_received.duplicate()}

@rpc("authority", "call_remote", "unreliable", 2)
func _fast(round_id: int, frame: int, index: int, count: int, data: PackedByteArray) -> void:
	if round_id != epoch or frame <= received_id or frame < fragment_id or count < 1 or count > 64 or index < 0 or index >= count or data.size() > 1000:
		return
	if frame != fragment_id:
		fragment_id = frame
		fragments.clear()
		fragments.resize(count)
		fragments_left = count
	if count != fragments.size() or not fragments[index].is_empty():
		return
	fragments[index] = data
	fragments_left -= 1
	if fragments_left == 0:
		var packed := PackedByteArray()
		for part in fragments:
			packed.append_array(part)
		_accept(bytes_to_var(packed.decompress_dynamic(65536, FileAccess.COMPRESSION_DEFLATE)))

func _send_fast() -> void:
	var packet := _snapshot()
	# Compress before splitting; each RPC fits a normal internet UDP datagram.
	# Missing chunks discard only this frame; every frame contains complete state.
	var packed := var_to_bytes(packet).compress(FileAccess.COMPRESSION_DEFLATE)
	var count := ceili(packed.size() / 1000.0)
	for i in range(count):
		_fast.rpc(epoch, packet.id, i, count, packed.slice(i * 1000, (i + 1) * 1000))

@rpc("authority", "call_remote", "reliable")
func _reliable(packet: Dictionary) -> void:
	_accept(packet)

func _accept(packet: Dictionary, first: bool = false) -> void:
	if packet.epoch != epoch or packet.id <= received_id or shell.game == null:
		return
	received_id = packet.id
	shop_round = packet.shop
	shop_ready.assign(packet.ready)
	move_ack = packet.ack.get(multiplayer.get_unique_id(), 0)
	State.apply(shell.game, packet.state, first)

func finish() -> void:
	if hosting:
		_finish.rpc(epoch, _snapshot())

@rpc("authority", "call_local", "reliable")
func _finish(round_id: int, packet: Dictionary) -> void:
	if round_id != epoch:
		return
	if not hosting:
		_accept(packet, true)
	phase = "result"
	shell.set_page("online_result")
	changed.emit()

func back_to_lobby() -> void:
	if hosting and phase == "result":
		_lobby.rpc()

@rpc("authority", "call_local", "reliable")
func _lobby() -> void:
	shell.game.free()
	shell.game = null
	actors.clear()
	phase = "lobby"
	for member in members.values():
		member.ready = false
	shell.set_page("online")
	changed.emit()

func _physics_process(delta: float) -> void:
	if not active:
		return
	elapsed += delta
	if phase in ["connecting", "loading"] and elapsed > 20.0:
		close("连接或加载超时，请确认双方使用相同版本并重新建房。")
		return
	if phase != "playing":
		return
	send_clock += delta
	input_clock += delta
	if not shell.simulation_mode and not local_menu and shell.game.is_playing() and input_clock >= 0.04:
		input_clock = 0.0
		if Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
			move_to(shell.game.ground_point(get_viewport().get_mouse_position()))
	if hosting and send_clock >= 0.04:
		send_clock = 0.0
		if members.size() > 1:
			var event: Array = [shell.game.score, shop_round, shell.game.shop_open]
			if event != last_event:
				last_event = event.duplicate(true)
				_reliable.rpc(_snapshot())
			else:
				_send_fast()
	elif not hosting:
		State.render(shell.game, delta)

func _allowed(id: int, round_id: int) -> bool:
	if not hosting or phase != "playing" or round_id != epoch or not actors.has(id):
		return false
	var second := Time.get_ticks_msec() / 1000
	var budget: Array = command_budget.get(id, [second, 0])
	if budget[0] != second:
		budget = [second, 0]
	budget[1] += 1
	command_budget[id] = budget
	return budget[1] <= 100

func move_to(point: Variant) -> void:
	if point == null or not point.is_finite() or local_menu or phase != "playing" or not shell.game.is_playing():
		return
	move_sequence += 1
	if hosting:
		_move(1, epoch, move_sequence, point)
	else:
		shell.game.player.target = shell.game.player.constrain_position(point)
		_motion.rpc_id(1, epoch, move_sequence, point)
	if not shell.simulation_mode:
		shell.game.marker.position = shell.game.player.target + Vector3.UP * 0.07
		shell.game.marker_time = 0.65

@rpc("any_peer", "call_remote", "unreliable_ordered", 1)
func _motion(round_id: int, sequence: int, point: Vector3) -> void:
	_move(multiplayer.get_remote_sender_id(), round_id, sequence, point)

func _move(id: int, round_id: int, sequence: int, point: Vector3) -> void:
	if not _allowed(id, round_id) or not point.is_finite() or sequence <= move_received.get(id, 0) or not shell.game.is_playing():
		return
	move_received[id] = sequence
	var actor = shell.game.players[actors[id]]
	actor.target = actor.constrain_position(point)

func order(action: String, value: int = 0, point: Vector3 = Vector3.ZERO) -> void:
	if phase != "playing":
		return
	if action in ["buy", "sell", "buy_e", "equip_e", "formation", "ready"]:
		shell.audio.play_ui("confirm" if action == "ready" else "click")
	if hosting:
		_order(1, epoch, shop_round, action, value, point, move_sequence)
	else:
		_command.rpc_id(1, epoch, shop_round, action, value, point, move_sequence)

@rpc("any_peer", "call_remote", "reliable")
func _command(round_id: int, shop_id: int, action: String, value: int, point: Vector3, barrier: int) -> void:
	_order(multiplayer.get_remote_sender_id(), round_id, shop_id, action, value, point, barrier)

func _order(id: int, round_id: int, shop_id: int, action: String, value: int, point: Vector3, barrier: int) -> void:
	if not _allowed(id, round_id) or not point.is_finite():
		return
	if action in ["stop", "face", "cancel"]:
		move_received[id] = maxi(move_received.get(id, 0), barrier)
	point.y = 0.0
	var game = shell.game
	var actor = game.players[actors[id]]
	if action == "cancel":
		actor.cancel_charge()
		actor.target = actor.position
		return
	if game.shop_open and shop_id == shop_round:
		var success := false
		match action:
			"ready":
				if id not in shop_ready:
					shop_ready.append(id)
				if shop_ready.size() == members.size():
					game.skip_shop()
				return
			"buy":
				if value >= 0 and value < game.Gear.ITEMS.size():
					success = game.buy_item(actor, value)
			"sell":
				if value >= 0 and value < actor.inventory.size():
					success = game.sell_item(actor, value)
			"buy_e", "equip_e":
				if value >= 0 and value < game.ESkills.SKILLS.size():
					success = game.buy_e(actor, value) if action == "buy_e" else game.equip_e(actor, value)
			"formation":
				if value >= 0 and value < game.Formations.NAMES.size():
					game.team_formations[actor.team] = value
					game.assign_formation(actor.team)
					success = true
		_feedback_to(id, "操作完成" if success else "无法购买或切换，请检查金币、配方和技能限制。")
		return
	if not game.is_playing():
		return
	match action:
		"timeout":
			var reason: String = game.timeout_error(actor.team)
			if not game.request_timeout(actor.team):
				_feedback_to(id, reason)
		"q": game.actor_kick(actor)
		"w":
			var direction: Vector3 = actor.facing
			if actor.archetype == game.Roles.Kind.STRIKER and point.distance_to(actor.position) > 0.1:
				direction = (point - actor.position).normalized()
			game.use_ability(actor, direction, point)
		"release": game.release_ability(actor)
		"e": game.use_e(actor, point)
		"stop":
			actor.target = actor.position
			actor.velocity = Vector3.ZERO
		"face":
			if not actor.action_blocked() and point.distance_to(actor.position) > 0.2:
				actor.target = actor.position
				actor.velocity = Vector3.ZERO
				actor.facing = (Vector3(point.x, 0, point.z) - actor.position).normalized()

func _feedback_to(id: int, text: String) -> void:
	if id == 1:
		shell.game.shop_feedback = text
		if not shell.game.shop_open:
			shell.game.announce(text, 2.0)
	else:
		_feedback.rpc_id(id, text)

@rpc("authority", "call_remote", "reliable")
func _feedback(text: String) -> void:
	if shell.game != null:
		shell.game.shop_feedback = text
		if not shell.game.shop_open:
			shell.game.announce(text, 2.0)

func handle_input(event: InputEvent) -> void:
	var game = shell.game
	if event is InputEventKey and event.physical_keycode == KEY_W and not event.pressed:
		order("release")
		return
	if event is InputEventKey and event.pressed and not event.echo:
		match event.physical_keycode:
			KEY_ESCAPE:
				local_menu = not local_menu
				order("cancel")
			KEY_H: game.help_visible = not game.help_visible
			KEY_Y: game.camera_locked = not game.camera_locked
			KEY_TAB: game.overview = not game.overview
			KEY_SPACE:
				game.camera_locked = true
				game.overview = false
			KEY_ENTER:
				if not local_menu and game.shop_open:
					order("ready")
			KEY_P:
				if not local_menu:
					order("timeout")
		if local_menu or not game.is_playing():
			return
		var point: Variant = game.ground_point(get_viewport().get_mouse_position())
		match event.physical_keycode:
			KEY_Q: order("q")
			KEY_S: order("stop")
			KEY_E, KEY_W:
				if point != null:
					order("e" if event.physical_keycode == KEY_E else "w", 0, point)
	if not event is InputEventMouseButton or not event.pressed or local_menu:
		return
	if event.button_index == MOUSE_BUTTON_WHEEL_UP:
		game.zoom_size = maxf(30, game.zoom_size - 3)
	elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		game.zoom_size = minf(63, game.zoom_size + 3)
	elif game.shop_open and event.button_index == MOUSE_BUTTON_LEFT:
		var hud = game.hud
		for tab in range(4):
			if hud.shop_tab_rect(tab).has_point(event.position):
				hud.shop_tab = tab
				return
		var formation: int = hud.formation_at(event.position)
		if formation >= 0:
			order("formation", formation)
			return
		if hud.shop_tab == 2:
			for id in game.ESkills.visible_skills(game.player.archetype):
				var rect: Rect2 = hud.shop_e_rect(id)
				if rect.has_point(event.position):
					order("buy_e" if event.position.y >= rect.position.y + 115 else "equip_e", id)
			return
		var item: int = hud.shop_item_at(event.position)
		var slot: int = hud.inventory_slot_at(event.position)
		if item >= 0:
			order("buy", item)
		elif slot >= 0:
			order("sell", slot)
	elif game.is_playing():
		var point: Variant = game.ground_point(event.position)
		if point != null:
			if event.button_index == MOUSE_BUTTON_RIGHT:
				move_to(point)
			elif event.button_index == MOUSE_BUTTON_LEFT:
				order("face", 0, point)
