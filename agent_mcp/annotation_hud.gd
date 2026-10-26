extends "res://scripts/hud.gd"
## MCP-only annotation patch; never loaded by the player build.
var annotations_enabled := true


func _status_labels() -> void:
	if not annotations_enabled:
		super._status_labels()
		return
	if not game.started or game.paused or game.finished or game.shop_open or game.help_visible:
		return
	var camera: Camera3D = game.camera
	var bounds := Rect2(24, 108, size.x - 48, size.y - 280)
	var occupied: Array[Rect2] = [Rect2(size.x - 284, 82, 260, 150), Rect2(size.x - 260, size.y - 182, 238, 160)]
	if game.mode in ["conquest", "rogue"]:
		occupied.append(Rect2(24, 108, 420, 112))
	elif game.mode in ["tutorial", "training"]:
		occupied.append(Rect2(20, 161, 438, 178 if game.mode == "tutorial" else 346))
	if game.announcement_time > 0 or game.goal_pause > 0:
		occupied.append(Rect2(size.x * 0.5 - 260, 140, 520, 48))
	var ball_point: Vector2 = camera.unproject_position(game.ball.position)
	occupied.append(Rect2(ball_point - Vector2(18, 30), Vector2(36, 48)))
	var entries: Array[Dictionary] = []
	for actor in game.players:
		var head: Vector3 = actor.position + Vector3.UP * 2.8
		if camera.is_position_behind(head):
			continue
		var anchor := camera.unproject_position(head)
		var foot := camera.unproject_position(actor.position)
		# Keep labels off players and the ball, not just off other text.
		occupied.append(Rect2(anchor - Vector2(14, 3), Vector2(28, maxf(foot.y - anchor.y, 0) + 8)))
		var status: String = actor.status_text()
		if status.is_empty() or not bounds.has_point(anchor):
			continue
		var priority := 0 if actor == game.player else (1 if actor == game.carrier else 2)
		entries.append({"anchor": anchor, "text": "%s%d  %s" % ["蓝" if actor.team == 0 else "红", actor.shirt_number, status],
			"color": BLUE if actor.team == 0 else CORAL, "priority": priority * 100 + actor.team * 20 + actor.shirt_number})
	entries.sort_custom(func(a, b): return a.priority < b.priority)
	var toward_camera := Vector3(camera.global_basis.z.x, 0, camera.global_basis.z.z).normalized()
	for field in game.fields:
		# Put area details on the near rim instead of covering the central contest.
		var anchor := camera.unproject_position(field.position + toward_camera * field.radius + Vector3.UP * 0.2)
		if bounds.has_point(anchor):
			entries.append({"anchor": anchor, "text": field.label_text, "color": BLUE if field.team == 0 else CORAL})
	var placed: Array[Dictionary] = []
	for entry in entries:
		var label_size := Vector2(font.get_string_size(entry.text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x + 18, 23)
		var rect := _status_rect(entry.anchor, label_size, occupied, bounds)
		if not rect.has_area():
			continue
		occupied.append(rect.grow(3))
		entry.rect = rect
		placed.append(entry)
		var tether := Vector2(clampf(entry.anchor.x, rect.position.x + 4, rect.end.x - 4), clampf(entry.anchor.y, rect.position.y, rect.end.y))
		draw_line(tether, entry.anchor, INK, 3, true)
		draw_line(tether, entry.anchor, entry.color, 1, true)
	# Draw all tethers underneath the badges so they cannot cross their text.
	for entry in placed:
		var rect: Rect2 = entry.rect
		_panel(rect, Color("#11151cf2"), 2)
		draw_rect(Rect2(rect.position, Vector2(3, rect.size.y)), entry.color)
		_text(entry.text, rect.position + Vector2(9, 16), 13, PAPER)


func _status_rect(anchor: Vector2, label_size: Vector2, occupied: Array[Rect2], bounds: Rect2) -> Rect2:
	for row in range(10):
		for y in [-30 - row * 27, 6 + row * 27]:
			for column in [0, -1, 1]:
				var offset := Vector2(column * (label_size.x + 8), y)
				var rect := Rect2(anchor + offset - Vector2(label_size.x * 0.5, 0), label_size)
				if bounds.encloses(rect) and not occupied.any(func(other): return rect.intersects(other)):
					return rect
	return Rect2()


