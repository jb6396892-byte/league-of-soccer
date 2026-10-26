extends RefCounted
## Expedition growth, weighted rewards and immutable milestone checkpoints.
const Roles = preload("res://scripts/archetypes.gd")
const Forms = preload("res://scripts/formations.gd")
const ES = preload("res://scripts/purchasable_skills.gd")
const STAGES := 20
const CHECKPOINTS := [5, 10, 15]
const QUALITY_NAMES := ["普通", "稀有", "强力"]
const QUALITY_WEIGHTS := [60, 30, 10]
const QUALITY_SCALE := [1.0, 1.6, 2.3]
const E_COOLDOWNS := [16.0, 22.0, 18.0]
const OPPONENTS := [3, 4, 5, 5, 6, 6, 7, 7, 8, 8, 9, 9, 10, 10, 11, 11, 11, 11, 11, 11]
const ELITE_STEP := {"speed": 0.012, "kick": 0.025, "haste": 0.025}
const MAX_ASCENSION := 5
const ASCENSION_NAMES := ["初始远征", "紧逼", "军备竞赛", "稀缺", "代价", "最终试验"]
const ASCENSION_RULES := [
	"原版规则，通关解锁进阶 1。",
	"对手初始移速 +5%，持续整轮远征。",
	"第 6 关起对手每关额外成长：移速 +1%、踢力 +2%、急速 +1.5%。",
	"普通 / 稀有 / 强力天赋概率改为 80% / 17% / 3%。",
	"每个休息处必将一份稀有或强力数值天赋降一级；保留类型。",
	"最终试验以 0:1 落后开局，对手额外强化速度、踢力、急速、控球与扑救。"
]
const ASCENSION_GROWTH_START := 5
const ASCENSION_GROWTH := {"speed": 0.01, "kick": 0.02, "haste": 0.015}
const SCARCE_WEIGHTS := [80, 17, 3]
const FINAL_TRIAL := {"speed": 0.08, "kick": 0.18, "haste": 0.20, "protection": 0.25, "slow_resist": 0.30, "save_window": 0.25}
const CROWNS := {
	"captain": {"name": "王者号令", "detail": "全队移速 +10% / 踢力 +15%", "scope": "team", "bonuses": {"speed": 0.10, "kick": 0.15}},
	"fortress": {"name": "不落城塞", "detail": "全队抗晕 +25% / 接球保护 +0.4秒", "scope": "team", "bonuses": {"stun_resist": 0.25, "protection": 0.4}},
	"ace": {"name": "王牌核心", "detail": "你的移速 +16% / 接球判定 +20%", "scope": "player", "bonuses": {"speed": 0.16, "size": 0.20}},
	"engine": {"name": "永动战术", "detail": "全队技能急速 +40% / 抗减速 +20%", "scope": "team", "bonuses": {"haste": 0.40, "slow_resist": 0.20}},
	"guardian": {"name": "门神契约", "detail": "门将移速 +15% / 扑救窗口 +0.6秒", "scope": "keeper", "bonuses": {"speed": 0.15, "save_window": 0.6}},
	"cannon": {"name": "决胜重炮", "detail": "你的踢力 +35% / 技能急速 +35%", "scope": "player", "bonuses": {"kick": 0.35, "haste": 0.35}}
}
const TALENTS := {
	"pace": {"name": "全队步频", "detail": "全队移速 +6%（含后续队友）", "key": "speed", "value": 0.06, "cap": 4, "scope": "team"},
	"power": {"name": "射门训练", "detail": "全队踢球力度 +10%", "key": "kick", "value": 0.10, "cap": 4, "scope": "team"},
	"runner": {"name": "个人突破", "detail": "你的移速 +9%", "key": "speed", "value": 0.09, "cap": 4, "scope": "player"},
	"finisher": {"name": "终结本能", "detail": "你的踢球力度 +18%", "key": "kick", "value": 0.18, "cap": 3, "scope": "player"},
	"reach": {"name": "争球专家", "detail": "你的接球 / 争球判定 +10%", "key": "size", "value": 0.10, "cap": 3, "scope": "player"},
	"control": {"name": "稳健第一脚", "detail": "全队接球保护 +0.25 秒", "key": "protection", "value": 0.25, "cap": 3, "scope": "team"},
	"resist": {"name": "抗压训练", "detail": "全队控制抗性 +12%", "key": "slow_resist", "value": 0.12, "cap": 3, "scope": "team"},
	"haste": {"name": "技能操练", "detail": "你的 W/E 技能急速 +20%", "key": "haste", "value": 0.20, "cap": 4, "scope": "player"},
	"keeper": {"name": "门线专训", "detail": "己方门将扑救窗口", "key": "save_window", "value": 0.18, "cap": 3, "scope": "keeper"},
	"resolve": {"name": "坚定意志", "detail": "全队眩晕抗性", "key": "stun_resist", "value": 0.08, "cap": 3, "scope": "team"},
	"team_haste": {"name": "战术默契", "detail": "全队 W 技能急速", "key": "haste", "value": 0.10, "cap": 3, "scope": "team"},
	"gloves": {"name": "门将步法", "detail": "己方门将移速", "key": "speed", "value": 0.08, "cap": 3, "scope": "keeper"},
	"outlet": {"name": "后场出球", "detail": "己方门将踢球力度", "key": "kick", "value": 0.12, "cap": 3, "scope": "keeper"},
	"team_reach": {"name": "协同争球", "detail": "全队接球判定", "key": "size", "value": 0.05, "cap": 3, "scope": "team"},
	"shield": {"name": "盘带屏障", "detail": "你的接球保护", "key": "protection", "value": 0.20, "cap": 3, "scope": "player"}
}
var stage := 1
var ascension := 0
var curses: Array[Dictionary] = []
var start_line := Forms.Line.FRONT
var members: Array[int] = []
var talents: Dictionary = {}
var talent_power: Dictionary = {}
var team_bonuses: Dictionary = {}
var crowns: Array[String] = []
var checkpoint: Dictionary = {}
var checkpoint_choice := false
var w_quality := 0
var e_quality := 0
var w_skill := -1
var e_skill := -1
var offers: Array[Dictionary] = []
var awaiting_reward := false
var ended := false
var seed_value: int
var rng := RandomNumberGenerator.new()


func _init(line: int = Forms.Line.FRONT, run_seed: int = 0, level: int = 0) -> void:
	start_line = line
	ascension = level
	if run_seed == 0:
		rng.randomize()
		seed_value = rng.randi()
	else:
		seed_value = run_seed
	rng.seed = seed_value
	members.assign({1: [0, 1], 2: [0, 5], 3: [0, 1]}[line])


func opponent_count() -> int:
	return OPPONENTS[stage - 1]


func difficulty() -> int:
	return 2


func enemy_bonuses() -> Dictionary:
	var elite := maxi(0, stage - 10)
	var bonuses := {"speed": elite * ELITE_STEP.speed, "kick": elite * ELITE_STEP.kick, "haste": elite * ELITE_STEP.haste}
	if ascension >= 1:
		bonuses.speed += 0.05
	if ascension >= 2:
		for key in ASCENSION_GROWTH:
			bonuses[key] += maxi(0, stage - ASCENSION_GROWTH_START) * ASCENSION_GROWTH[key]
	if ascension >= 5 and stage == STAGES:
		for key in FINAL_TRIAL:
			bonuses[key] = bonuses.get(key, 0.0) + FINAL_TRIAL[key]
	return bonuses


static func quality_weights(level: int) -> Array:
	return SCARCE_WEIGHTS if level >= 3 else QUALITY_WEIGHTS


static func quality_text(level: int) -> String:
	return "普通 %d%% / 稀有 %d%% / 强力 %d%%" % quality_weights(level)


func trim_rosters(game: Node) -> void:
	for team in range(2):
		var count: int = members.size() + 2 if team == 0 else opponent_count()
		while game.players.filter(func(p): return p.team == team).size() > count:
			var actor = game.players.filter(func(p): return p.team == team and not p.goalkeeper and p != game.player).back()
			game.players.erase(actor)
			actor.free()
	var allies: Array = game.players.filter(func(p): return p.team == 0 and not p.goalkeeper and p != game.player)
	for i in range(allies.size()):
		allies[i].set_archetype(members[i])
	game.player.rogue_player = true
	game.player.w_unlocked = w_skill >= 0
	game.player.set_archetype(w_skill if w_skill >= 0 else Roles.Kind.RUNNER)


static func slots(field_count: int) -> Array:
	# Small squads retain a back, a midfielder and a forward.
	var counts := [1, 1, 1]
	if field_count == 2:
		counts = [1, 0, 1]
	var additions := [0, 1, 0, 2, 1, 0, 1]
	for i in range(maxi(0, field_count - 3)):
		counts[additions[i]] += 1
	var result: Array = []
	for row in range(3):
		for column in range(counts[row]):
			var z := 0.0 if counts[row] == 1 else lerpf(-18, 18, float(column) / (counts[row] - 1))
			result.append({"home": Vector3([-32, -18, -6][row], 0, z), "line": row + 1})
	return result


func assign_team(game: Node, team: int, fresh: bool) -> void:
	var sign_x := 1.0 if team == 0 else -1.0
	var pool: Array = game.players.filter(func(p): return p.team == team and not p.goalkeeper)
	var places := slots(pool.size())
	var keeper = game.players.filter(func(p): return p.team == team and p.goalkeeper)[0]
	keeper.home = Vector3(-44.5 * sign_x, 0, 0)
	keeper.tactical_line = Forms.Line.KEEPER
	if team == 0:
		pool.erase(game.player)
		pool.push_front(game.player)
	for actor in pool:
		var preferred: int = start_line if actor == game.player else Forms.PREFERRED_LINE[actor.archetype]
		var matching := places.filter(func(s): return s.line == preferred)
		matching.sort_custom(func(a, b): return absf(a.home.z) < absf(b.home.z))
		var place: Dictionary = matching[0] if not matching.is_empty() else places[0]
		if team == 1 and fresh:
			place = places[0]
			actor.set_archetype(Forms.random_hero(place.line, game.rng))
		actor.home = place.home * sign_x
		actor.tactical_line = place.line
		places.erase(place)


func applies(scope: String, actor: Node, player: Node) -> bool:
	return scope == "team" or (scope == "player" and actor == player) or (scope == "keeper" and actor.goalkeeper)


func apply_growth(game: Node) -> void:
	for actor in game.players:
		actor.gold = 0
		actor.extra_bonuses.clear()
		if actor.team == 1:
			actor.extra_bonuses = enemy_bonuses()
			continue
		actor.extra_bonuses = team_bonuses.duplicate()
		for id in talents:
			var talent: Dictionary = TALENTS[id]
			if applies(talent.scope, actor, game.player):
				actor.extra_bonuses[talent.key] = actor.extra_bonuses.get(talent.key, 0.0) + talent_power.get(id, float(talents[id])) * talent.value
		for id in crowns:
			if applies(CROWNS[id].scope, actor, game.player):
				for key in CROWNS[id].bonuses:
					actor.extra_bonuses[key] = actor.extra_bonuses.get(key, 0.0) + CROWNS[id].bonuses[key]
		# Prevent stacked control immunity or excessive permanent possession protection.
		actor.extra_bonuses.stun_resist = minf(0.65, actor.extra_bonuses.get("stun_resist", 0.0))
		actor.extra_bonuses.protection = minf(1.2, actor.extra_bonuses.get("protection", 0.0))
	game.player.extra_bonuses.haste = game.player.extra_bonuses.get("haste", 0.0) + w_quality * 0.15
	game.player.e_selected = e_skill
	game.player.e_unlimited = e_skill >= 0


static func quality_for_roll(roll: int, level: int = 0) -> int:
	var weights := quality_weights(level)
	return 0 if roll < weights[0] else (1 if roll < weights[0] + weights[1] else 2)


func e_detail(quality: int, skill: int) -> String:
	return ["移速 +%d%% / 1.8秒" % (10 + quality * 2), "解控 / 免控 %.1f秒" % (0.7 + quality * 0.2), "持球保护 %.2f秒" % (0.6 + quality * 0.15)][skill] + " / CD %d秒" % E_COOLDOWNS[skill]


func decorate(offer: Dictionary) -> Dictionary:
	var q := quality_for_roll(rng.randi_range(0, 99), ascension)
	offer.quality = q
	offer.tag = QUALITY_NAMES[q] + " · " + offer.tag
	match offer.type:
		"stat":
			var t: Dictionary = TALENTS[offer.value]
			var amount: float = t.value * QUALITY_SCALE[q]
			var unit := "%.2f秒" % amount if t.key in ["protection", "save_window"] else "%.1f%%" % (amount * 100)
			offer.detail = {"team": "全队", "player": "你的", "keeper": "己方门将"}[t.scope] + {"speed": "移速", "kick": "踢力", "size": "接球判定", "protection": "接球保护", "haste": "技能急速", "slow_resist": "抗减速", "stun_resist": "抗眩晕", "save_window": "扑救窗口"}[t.key] + " +" + unit
		"recruit":
			offer.detail = "队友 +1，继承全队天赋"
			if q > 0:
				offer.detail += "；全队移速 +%d%% / 踢力 +%d%%" % [q * 2, q * 3]
		"w":
			offer.detail += "；技能急速 +%d%%" % (q * 15)
		"e":
			offer.detail = e_detail(q, offer.value)
	return offer


func reward() -> void:
	assert(not awaiting_reward and not ended and stage < STAGES)
	awaiting_reward = true
	checkpoint_choice = false
	offers.clear()
	if members.size() < 9:
		var hero: int = [0, 1, 2, 3, 5][rng.randi_range(0, 4)]
		offers.append(decorate({"type": "recruit", "value": hero, "name": "队友 +1 · " + Roles.NAMES[hero], "tag": "阵容 %d → %d 人" % [members.size() + 2, members.size() + 3]}))
	var stats: Array = TALENTS.keys().filter(func(id): return talents.get(id, 0) < TALENTS[id].cap and (id != "haste" or w_skill >= 0 or e_skill >= 0))
	var skills: Array[Dictionary] = []
	if w_skill < 0:
		for kind in [0, 1, 2, 3, 5]:
			skills.append({"type": "w", "value": kind, "name": "学习 W · " + Roles.W_NAMES[kind], "detail": Roles.W_DETAILS[kind], "tag": "常驻 W 技能"})
	if e_skill < 0:
		for kind in [0, 1, 2]:
			skills.append({"type": "e", "value": kind, "name": "学习 E · " + ES.SKILLS[kind].name, "tag": "无限次 · 弱化 E"})
	if not skills.is_empty():
		offers.append(decorate(skills[rng.randi_range(0, skills.size() - 1)]))
	while offers.size() < 3:
		var id: String = stats.pop_at(rng.randi_range(0, stats.size() - 1))
		var talent: Dictionary = TALENTS[id]
		offers.append(decorate({"type": "stat", "value": id, "name": talent.name, "tag": "升级 %d / %d" % [talents.get(id, 0) + 1, talent.cap]}))
	var swap := rng.randi_range(0, 2)
	var first: Dictionary = offers[0]
	offers[0] = offers[swap]
	offers[swap] = first


func crown_reward() -> void:
	apply_rest_curse()
	checkpoint_choice = true
	awaiting_reward = true
	offers.clear()
	var pool: Array = CROWNS.keys().filter(func(id): return id not in crowns)
	for i in range(3):
		var id: String = pool.pop_at(rng.randi_range(0, pool.size() - 1))
		offers.append({"type": "crown", "value": id, "name": CROWNS[id].name, "detail": CROWNS[id].detail, "tag": "存档点专属 · 顶级", "quality": 3})


static func ranks_for_power(count: int, power: float) -> Array[int]:
	# With caps <= 4, the 1 / 1.6 / 2.3 weights uniquely identify the owned ranks.
	# Reconstructing them also preserves pre-ascension saves without inventing quality.
	for strong in range(count + 1):
		for rare in range(count - strong + 1):
			var common := count - strong - rare
			if is_equal_approx(power, common + rare * QUALITY_SCALE[1] + strong * QUALITY_SCALE[2]):
				var ranks: Array[int] = []
				for q in range(3):
					for i in range([common, rare, strong][q]):
						ranks.append(q)
				return ranks
	return []


func apply_rest_curse() -> void:
	if ascension < 4 or stage not in CHECKPOINTS or curses.any(func(c): return c.stage == stage):
		return
	var pool: Array[Dictionary] = []
	for id in talents:
		for q in ranks_for_power(talents[id], talent_power.get(id, float(talents[id]))):
			if q > 0:
				pool.append({"id": String(id), "from": q, "to": q - 1})
	var event := {"stage": stage, "id": "", "from": 0, "to": 0}
	if not pool.is_empty():
		# A separate deterministic stream keeps reward rolls comparable across ascensions.
		var curse_rng := RandomNumberGenerator.new()
		curse_rng.seed = seed_value + stage * 7919
		event.merge(pool[curse_rng.randi_range(0, pool.size() - 1)], true)
		talent_power[event.id] -= QUALITY_SCALE[event.from] - QUALITY_SCALE[event.to]
		# Avoid floating-point drift below the minimum rank after several downgrades.
		talent_power[event.id] = snappedf(talent_power[event.id], 0.1)
	curses.append(event)


func curse_text() -> String:
	if curses.is_empty() or curses.back().stage != stage:
		return ""
	var event: Dictionary = curses.back()
	if event.id.is_empty():
		return "休息处诅咒：没有可降级的数值天赋。队友、技能与顶级天赋保留。"
	return "休息处诅咒：%s 的一份 %s → %s。结果随存档固定。" % [TALENTS[event.id].name, QUALITY_NAMES[event.from], QUALITY_NAMES[event.to]]


func choose(index: int) -> bool:
	if not awaiting_reward or ended or index < 0 or index >= offers.size():
		return false
	var offer: Dictionary = offers[index]
	match offer.type:
		"recruit":
			members.append(offer.value)
			team_bonuses.speed = team_bonuses.get("speed", 0.0) + offer.quality * 0.02
			team_bonuses.kick = team_bonuses.get("kick", 0.0) + offer.quality * 0.03
		"w":
			w_skill = offer.value
			w_quality = offer.quality
		"e":
			e_skill = offer.value
			e_quality = offer.quality
		"stat":
			talent_power[offer.value] = talent_power.get(offer.value, float(talents.get(offer.value, 0))) + QUALITY_SCALE[offer.quality]
			talents[offer.value] = talents.get(offer.value, 0) + 1
		"crown": crowns.append(offer.value)
	awaiting_reward = false
	offers.clear()
	if stage in CHECKPOINTS and not checkpoint_choice:
		crown_reward()
		return true
	stage += 1
	if checkpoint_choice:
		checkpoint_choice = false
		checkpoint = snapshot()
	return true


func snapshot() -> Dictionary:
	return {"stage": stage, "ascension": ascension, "curses": curses.duplicate(true), "line": start_line, "members": members.duplicate(), "talents": talents.duplicate(), "power": talent_power.duplicate(), "team": team_bonuses.duplicate(), "crowns": crowns.duplicate(), "w": w_skill, "e": e_skill, "wq": w_quality, "eq": e_quality, "seed": seed_value, "rng": rng.state}


func restore(data: Dictionary) -> bool:
	# This is a disk input boundary. Reject incomplete/incompatible snapshots before mutation.
	for key in ["stage", "line", "members", "talents", "power", "team", "crowns", "w", "e", "wq", "eq", "seed", "rng"]:
		if not data.has(key): return false
	if data.stage not in [6, 11, 16] or data.line not in [1, 2, 3] or data.w not in [-1, 0, 1, 2, 3, 5] or data.e not in [-1, 0, 1, 2] or data.wq not in [0, 1, 2] or data.eq not in [0, 1, 2]: return false
	if not data.members is Array or not data.crowns is Array or not data.talents is Dictionary or not data.power is Dictionary or not data.team is Dictionary or not data.seed is int or not data.rng is int: return false
	if data.members.size() < 2 or data.members.size() > 9 or data.crowns.size() != (data.stage - 1) / 5: return false
	var level = data.get("ascension", 0)
	var history = data.get("curses", [])
	if not level is int or level < 0 or level > MAX_ASCENSION or not history is Array: return false
	if history.size() != ((data.stage - 1) / 5 if level >= 4 else 0): return false
	for i in range(history.size()):
		var event = history[i]
		if not event is Dictionary or not event.has_all(["stage", "id", "from", "to"]): return false
		if event.stage != CHECKPOINTS[i] or not event.id is String: return false
		if event.id.is_empty():
			if event.from != 0 or event.to != 0: return false
		elif not data.talents.has(event.id) or event.from not in [1, 2] or event.to != event.from - 1:
			return false
	for member in data.members:
		if member not in [0, 1, 2, 3, 5]: return false
	var seen := {}
	for id in data.crowns:
		if not CROWNS.has(id) or seen.has(id): return false
		seen[id] = true
	for id in data.talents:
		if not TALENTS.has(id) or not data.talents[id] is int: return false
		if data.talents[id] < 1 or data.talents[id] > TALENTS[id].cap: return false
	for id in data.power:
		if not data.talents.has(id) or not (data.power[id] is float or data.power[id] is int): return false
		if not is_finite(data.power[id]) or data.power[id] < data.talents[id] or data.power[id] > data.talents[id] * 2.3 + 0.001: return false
		if ranks_for_power(data.talents[id], data.power[id]).is_empty(): return false
	for key in data.team:
		if key not in ["speed", "kick"] or not (data.team[key] is float or data.team[key] is int): return false
		if not is_finite(data.team[key]) or data.team[key] < 0 or data.team[key] > 0.5: return false
	stage = data.stage
	ascension = level
	curses.assign(history.duplicate(true))
	start_line = data.line
	members.assign(data.members)
	talents = data.talents.duplicate()
	talent_power = data.power.duplicate()
	team_bonuses = data.team.duplicate()
	crowns.assign(data.crowns)
	w_skill = data.w
	e_skill = data.e
	w_quality = data.wq
	e_quality = data.eq
	seed_value = data.seed
	rng.seed = seed_value
	rng.state = data.rng
	checkpoint = snapshot()
	ended = false
	awaiting_reward = false
	checkpoint_choice = false
	offers.clear()
	return true


func talent_kind_count() -> int:
	return talents.size() + crowns.size() + int(w_skill >= 0) + int(e_skill >= 0)


func build_lines() -> Array[String]:
	var lines: Array[String] = ["进阶 %d · %d 人 · %s" % [ascension, members.size() + 2, Forms.LINE_NAMES[start_line]],
		"W · " + (Roles.W_NAMES[w_skill] if w_skill >= 0 else "尚未学习"),
		"E · " + (ES.SKILLS[e_skill].name if e_skill >= 0 else "尚未学习")]
	for id in crowns:
		lines.append("顶级 · " + CROWNS[id].name)
	for id in talents:
		var ranks := ranks_for_power(talents[id], talent_power.get(id, float(talents[id])))
		var counts: Array[String] = []
		for q in range(3):
			if ranks.count(q) > 0:
				counts.append("%s%d" % [["普", "稀", "强"][q], ranks.count(q)])
		lines.append("%s · %s" % [TALENTS[id].name, " ".join(counts)])
	return lines
