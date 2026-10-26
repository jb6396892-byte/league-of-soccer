extends SceneTree
var host_shell: Node
var guest_shell: Node
var failures := 0
var checks := 0

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> bool:
	checks += 1
	if not ok:
		failures += 1
	print(("PASS: " if ok else "FAIL: ") + message)
	return ok

func until(predicate: Callable, message: String) -> bool:
	var deadline := Time.get_ticks_msec() + 6000
	while not predicate.call() and Time.get_ticks_msec() < deadline:
		await create_timer(0.03).timeout
	return check(predicate.call(), message)

func endpoint(label: String) -> Node:
	var branch := Node.new()
	branch.name = label
	root.add_child(branch)
	set_multiplayer(SceneMultiplayer.new(), branch.get_path())
	var shell = load("res://shell.tscn").instantiate()
	shell.simulation_mode = true
	shell.progress_path = "res://work/online-" + label + ".cfg"
	branch.add_child(shell)
	return shell

func run() -> void:
	create_timer(60).timeout.connect(func(): print("FAIL: network test timeout"); quit(1))
	host_shell = endpoint("Host")
	guest_shell = endpoint("Guest")
	var host = host_shell.net
	var guest = guest_shell.net
	var port := 26000 + Time.get_ticks_msec() % 1000
	host.host("房主", port)
	guest.join("127.0.0.1", "客机", port)
	if not await until(func(): return guest.members.size() == 2, "two real ENet endpoints register in one room"):
		print("HOST: ", host.message, " / ", host.phase, " / ", host.multiplayer.root_path)
		print("GUEST: ", guest.message, " / ", guest.phase, " / ", guest.multiplayer.root_path)
		finish()
		return
	var guest_id: int = guest.multiplayer.get_unique_id()
	host.select(0, 4, true)
	guest.select(1, 5, true)
	await until(func(): return host.can_start(), "opposing teams and distinct roles ready")
	host.start()
	if not await until(func(): return host.phase == "playing" and guest.phase == "playing", "both peers load before simulation starts"):
		finish()
		return
	var hg = host_shell.game
	var cg = guest_shell.game
	hg.set_physics_process(false)
	var remote = hg.players[host.actors[guest_id]]
	check(hg.player.goalkeeper and cg.player.team == 1 and cg.player.archetype == 5, "host keeper and red guest receive correct controls")
	check(hg.players.filter(func(a): return a.human).size() == 2, "exactly two humans, twenty NPCs")
	check(cg.player.local_controlled and not cg.players[host.actors[1]].local_controlled, "only local player has the personal selection marker")
	guest.order("buy", 0)
	await until(func(): return cg.player.inventory.size() == 1, "guest purchase travels to host and back")
	check(remote.gold == 380 and cg.player.gold == 380 and hg.player.gold == 500, "gold deducted only from purchasing player")
	guest.order("buy", 999)
	guest.order("buy", -1)
	guest.order("sell", 5)
	await create_timer(0.15).timeout
	check(remote.gold == 380 and remote.inventory.size() == 1, "invalid item IDs and empty sell slots are rejected")
	guest.order("buy_e", 0)
	await until(func(): return cg.player.e_charges.get(0, 0) == 1, "E charges synchronized separately from equipment")
	guest.order("ready")
	await until(func(): return host.shop_ready.size() == 1, "guest shop readiness registered")
	check(hg.shop_open, "one player cannot close both players' shop")
	host.order("ready")
	await until(func(): return not cg.shop_open, "both ready closes shop on both peers")
	guest.order("timeout")
	await create_timer(0.1).timeout
	check(not hg.shop_open and hg.timeout_tokens == [1, 1], "guest cannot call timeout without team possession")
	hg.carrier = remote
	guest.order("timeout")
	await until(func(): return cg.shop_open and cg.timeout_team == 1, "guest timeout opens the same shop on both peers")
	check(hg.timeout_tokens == [1, 0] and cg.timeout_tokens == [1, 0], "shared timeout stock is authoritative and synchronized")
	guest.order("formation", 2)
	await until(func(): return cg.team_formations[1] == 2, "formation can change during a requested timeout")
	guest.order("ready")
	host.order("ready")
	await until(func(): return not cg.shop_open and cg.kickoff_team == 1, "both ready gives the requesting red team centre kickoff")
	check(hg.carrier.team == 1 and cg.carrier.team == 1, "restart possession agrees on both peers")
	guest.move_to(Vector3(18, 0, 12))
	await until(func(): return remote.target.distance_to(Vector3(18, 0, 12)) < 0.01, "red player movement authorized and routed correctly")
	var old_host_target: Vector3 = hg.player.target
	check(old_host_target != remote.target, "guest input cannot steer host player")
	guest.order("stop")
	await until(func(): return remote.target.distance_to(remote.position) < 0.01, "stop command cancels movement")
	host._move(guest_id, host.epoch, 0, Vector3(20, 0, 20))
	check(remote.target == remote.position, "late movement packet cannot undo stop")
	guest._motion.rpc_id(1, guest.epoch, 100, Vector3(INF, 0, 0))
	await create_timer(0.1).timeout
	check(remote.target.is_finite(), "non-finite movement is rejected by authority")
	# Real W/E actions and corresponding visual entities; fixture freezes physics for precision.
	remote.ability_cooldown = 0
	guest.order("w", 0, Vector3.ZERO)
	await until(func(): return hg.fields.size() == 1 and cg.fields.size() == 1, "red W field spawned once and replicated")
	check(hg.fields[0].source == remote and cg.fields[0].source == cg.player, "field source and team preserved")
	guest.order("w", 0, Vector3.ZERO)
	await create_timer(0.12).timeout
	check(hg.fields.size() == 1, "W cooldown enforced on host")
	# Explicitly lose one chunk, then reorder the next frame. No partial state applies.
	host.set_physics_process(false)
	await create_timer(0.15).timeout
	var before: int = guest.received_id
	var incomplete: Dictionary = host._snapshot()
	var packed := var_to_bytes(incomplete).compress(FileAccess.COMPRESSION_DEFLATE)
	var half := packed.size() / 2
	guest._fast(host.epoch, incomplete.id, 0, 2, packed.slice(0, mini(half, 1000)))
	check(guest.received_id == before, "missing fragment does not apply partial state")
	var complete: Dictionary = host._snapshot()
	packed = var_to_bytes(complete).compress(FileAccess.COMPRESSION_DEFLATE)
	var count := ceili(packed.size() / 1000.0)
	for i in range(count - 1, -1, -1):
		guest._fast(host.epoch, complete.id, i, count, packed.slice(i * 1000, (i + 1) * 1000))
	check(guest.received_id == complete.id, "next complete frame recovers despite reordered fragments")
	guest._fast(host.epoch, incomplete.id, 0, 2, packed.slice(0, 1000))
	check(guest.received_id == complete.id, "late old frame cannot overwrite newer state")
	host.set_physics_process(true)
	guest.order("e")
	await until(func(): return remote.e_charges.get(0, 0) == 0 and cg.player.e_charges.get(0, 0) == 0, "successful E consumes exactly one charge on both peers")
	hg.carrier = remote
	hg.ball.position = remote.position + remote.facing * remote.control_distance() + Vector3.UP * hg.Ball.RADIUS
	remote.kick_cooldown = 0
	guest.order("q")
	await until(func(): return hg.carrier == null and cg.carrier == null and cg.ball.velocity.length() > 10, "Q kick and ball ownership replicated")
	var selected: int = remote.archetype
	guest.select(0, 0, true)
	await create_timer(0.1).timeout
	check(remote.archetype == selected, "role cannot be changed mid-match")
	hg.score = [1, 2]
	hg.time_left = 42.0
	await until(func(): return cg.score == [1, 2] and cg.time_left == 42.0, "score and clock share authoritative values")
	hg.finish_session(false)
	await until(func(): return guest.phase == "result", "final result reliably reaches guest")
	check(cg.score[cg.player.team] > cg.score[1 - cg.player.team], "red victory interpreted from guest's team")
	host.back_to_lobby()
	await until(func(): return guest.phase == "lobby", "rematch returns both peers to lobby")
	host.select(0, 4, true)
	guest.select(0, 4, true)
	await until(func(): return host.members[guest_id].role == 4, "guest choice delivered in lobby")
	check(not host.can_start(), "same team cannot have two human goalkeepers")
	host.select(0, 0, true)
	guest.select(0, 2, true)
	await until(func(): return host.can_start() and host.members[guest_id].role == 2, "cooperative room ready")
	host.start()
	await until(func(): return guest.phase == "playing" and host.phase == "playing", "cooperative match starts")
	hg = host_shell.game
	cg = guest_shell.game
	hg.set_physics_process(false)
	remote = hg.players[host.actors[guest_id]]
	check(remote.team == hg.player.team and remote != hg.player and remote.home != hg.player.home, "co-op gets distinct footballers and formation slots")
	check(hg.ai_profile(hg.players[5]) == hg.ai_profile(hg.players[15]), "both teams use the same selected AI difficulty online")
	# A human defender cannot execute an NPC marking assignment.
	var prior_carrier = hg.carrier
	var prior_difficulty: int = hg.difficulty
	var prior_position: Vector3 = remote.position
	var prior_local_position: Vector3 = hg.player.position
	remote.team = 1
	remote.position = hg.player.position + Vector3(0, 0, 1)
	hg.player.position.x = 6
	remote.position.x = 5
	hg.carrier = remote
	hg.difficulty = 2
	var coverage := {}
	hg._add_player_coverage(coverage, remote)
	check(coverage.size() == 1 and not coverage.has(hg.player) and coverage.keys().all(func(a): return not a.human), "hard AI assigns a real NPC instead of a human defender")
	remote.team = 0
	remote.position = prior_position
	hg.player.position = prior_local_position
	hg.carrier = prior_carrier
	hg.difficulty = prior_difficulty
	host.order("ready")
	guest.order("ready")
	await until(func(): return not cg.shop_open, "co-op shop readiness works")
	guest.order("w")
	await until(func(): return remote.charging, "guest charge begins on host")
	guest.order("release")
	await until(func(): return remote.dash_remaining > 0 and not remote.charging, "guest charge release triggers authoritative dash")
	guest.close()
	await until(func(): return not remote.human and host.members.size() == 1, "disconnected guest is replaced by an NPC")
	check(host.phase == "playing" and host_shell.game != null, "host match continues after guest disconnect")
	# Return and reconnect, then exercise explicit host shutdown.
	hg.finish_session(true)
	host.back_to_lobby()
	guest.join("127.0.0.1", "重连球员", port)
	await until(func(): return guest.members.size() == 2, "new connection can join the next lobby")
	host.close()
	await until(func(): return not guest.active and guest.phase == "offline", "host departure closes guest room cleanly")
	finish()

func finish() -> void:
	host_shell.net.close()
	guest_shell.net.close()
	root.get_node("Host").free()
	root.get_node("Guest").free()
	print("ONLINE RESULT: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
