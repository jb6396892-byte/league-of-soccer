extends RefCounted
## Legal right-click/aim/Q/W/E proxy, sampled every 0.2s. Not a human skill model.
static func aim_kick(game: Node, actor: Node, point: Vector3) -> void:
	if actor.action_blocked() or actor.kick_cooldown > 0:
		return
	var direction: Vector3 = point - actor.position
	direction.y = 0.0
	actor.target = actor.position
	actor.velocity = Vector3.ZERO
	actor.facing = direction.normalized()
	game.actor_kick(actor)

static func control(game: Node, actor: Node, variant: int) -> void:
	var attack := 1.0 if actor.team == 0 else -1.0
	var ball: Vector3 = game.ball.position
	ball.y = 0.0
	var aim := Vector3(52 * attack, 0, (-2.8 if variant % 2 == 0 else 2.8) * attack)
	var pressure: float = game.tactics.pressure(actor)
	if actor.goalkeeper:
		actor.target = actor.constrain_position(Vector3(-48 * attack, 0, clampf(ball.z * 0.3, -5, 5)))
		if ball.x * attack < -37 and ball.distance_to(actor.position) < 12:
			actor.target = actor.constrain_position(ball)
		if game.carrier == actor:
			var mate = game.tactics.pass_target(actor)
			aim_kick(game, actor, mate.position + mate.velocity * 0.3 if mate != null else Vector3(-20 * attack, 0, 24 if ball.z >= 0 else -24))
		elif game.carrier == null and ball.distance_to(actor.position) < 8:
			aim_kick(game, actor, ball)
	elif game.carrier == actor:
		actor.target = actor.constrain_position(Vector3(48 * attack, 0, actor.position.z * 0.65))
		if actor.position.x * attack > 27 and absf(actor.position.z) < 18:
			aim_kick(game, actor, aim)
		elif pressure < 5:
			var mate = game.tactics.pass_target(actor)
			if mate != null:
				aim_kick(game, actor, mate.position + mate.velocity * 0.3)
	elif game.carrier != null and game.carrier.team == actor.team:
		actor.target = actor.constrain_position(game.tactics.support(actor))
	else:
		actor.target = actor.constrain_position(ball + Vector3(game.ball.velocity.x, 0, game.ball.velocity.z) * 0.15)
		if actor.position.distance_to(ball) < 1.8 and ball.x * attack > 28:
			aim_kick(game, actor, aim)
	if actor.charging and actor.charge_time >= minf(0.55, actor.max_charge_time()):
		game.release_ability(actor)
	elif game._ai_wants_ability(actor, true):
		game.use_ability(actor, actor.facing, ball)
	if game._ai_wants_e(actor):
		game.use_e(actor, actor.target)
