extends Control
## Resolution-independent match HUD, rendered in the project's 1440 × 900 canvas.

const INK := Color("#11151c")
const PAPER := Color("#f2f3f5")
const MUTED := Color("#9ba4b2")
const LIME := Color("#c9ff41")
const BLUE := Color("#63a9ff")
const CORAL := Color("#ff6f78")
const Roles = preload("res://scripts/archetypes.gd")
const Gear = preload("res://scripts/equipment.gd")
const ESkills = preload("res://scripts/purchasable_skills.gd")
const Settings = preload("res://scripts/match_settings.gd")
const Formations = preload("res://scripts/formations.gd")
var game: Node3D
var font: SystemFont
var bold: SystemFont
var shop_tab := 0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	font = SystemFont.new()
	font.font_names = PackedStringArray(["Microsoft YaHei UI", "Microsoft YaHei", "Segoe UI"])
	bold = SystemFont.new()
	bold.font_names = font.font_names
	bold.font_weight = 700


func _draw() -> void:
	var w := size.x
	var h := size.y
	_status_labels()
	# Broadcast score: one compact block leaves the centre of the pitch clear.
	var seconds := int(ceil(game.time_left))
	var clock_text := "练习" if game.is_practice() else "%02d:%02d" % [seconds / 60, seconds % 60]
	if game.mode == "rogue" and game.overtime_count > 0:
		clock_text = "+%ds" % int(game.rogue_extra_time)
	_panel(Rect2(28, 24, 424, 54), Color("#11151cf2"), 2)
	draw_rect(Rect2(28, 24, 94, 54), LIME)
	_center(clock_text, Vector2(75, 59), 23, INK, true)
	draw_rect(Rect2(139, 40, 4, 21), BLUE)
	_text("蓝队", Vector2(153, 58), 18, PAPER, true)
	_center("%d  —  %d" % game.score, Vector2(281, 60), 26, PAPER, true)
	draw_rect(Rect2(354, 40, 4, 21), CORAL)
	_text("红队", Vector2(368, 58), 18, PAPER, true)
	var detail := "%s  /  队友%s · 对手%s" % [Formations.NAMES[game.team_formations[game.player.team]], Settings.NAMES[game.ai_difficulty(game.player.team)], Settings.NAMES[game.ai_difficulty(1 - game.player.team)]]
	if game.mode == "rogue":
		detail = "进阶 %d  /  %d v %d  /  困难 AI" % [game.rogue.ascension, game.rogue.members.size() + 2, game.rogue.opponent_count()]
		if game.rogue.ascension >= 5 and game.rogue.stage == game.rogue.STAGES:
			detail += "  /  强化最终试验"
	elif game.is_practice():
		detail = "自由练习  /  不限时"
	if game.overtime_count > 0:
		detail += "  /  金球加时" if game.mode == "rogue" else "  /  加时 %d" % game.overtime_count
	elif game.started and not game.finished and not game.is_practice() and game.mode != "rogue":
		detail += "  /  P 暂停 %d/2 · %ds 后 +1" % [game.timeout_tokens[game.player.team], ceili(Gear.SUPPLY_SECONDS - game.supply_clock)]
	_text(detail, Vector2(30, 99), 12, PAPER)
	if game.started:
		_bottom_bar(w, h)
		_minimap(Rect2(w - 254, h - 177, 226, 149))
		_controls(h)
		_wallet(w)
		if not game.shop_open and game.goal_pause > 0:
			_center("准备开球 · %d" % ceili(game.goal_pause), Vector2(w * 0.5, 172), 20, LIME, true)
		elif game.announcement_time > 0 and game.goal_pause <= 0:
			var text_width := font.get_string_size(game.announcement, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x
			_panel(Rect2(w * 0.5 - text_width * 0.5 - 24, 145, text_width + 48, 42), Color("#11151ce6"), 21)
			_center(game.announcement, Vector2(w * 0.5, 172), 16, PAPER)
		if game.help_visible:
			_help_panel(w, h)
	if not game.started:
		_start_screen(w, h)
	elif game.finished and game.net == null:
		_overlay(w, h, "终场哨响", "蓝队  %d  :  %d  珊瑚队" % game.score, "按 Enter 或单击，开始新比赛")
	elif game.paused and not game.shop_open:
		_overlay(w, h, "比赛已暂停", "远征中不能换角或重开本关" if game.mode == "rogue" else "1 / 2 / 3 / 4 / 5 / 6 选角并重新开局", "按 Esc 继续当前比赛")
	elif game.shop_open:
		_shop(w, h)
	_ball_indicator(w, h)


func _status_labels() -> void:
	if not game.started or game.paused or game.finished or game.shop_open or game.help_visible:
		return
	# Human play keeps one compact status badge. NPC effects use their visual tells.
	var status: String = game.player.status_text()
	if status.is_empty():
		return
	var point: Vector2 = game.camera.unproject_position(game.player.position + Vector3.UP * 3.3)
	var width := font.get_string_size(status, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x + 18
	var rect := Rect2(point - Vector2(width * 0.5, 25), Vector2(width, 23))
	_panel(rect, Color("#11151cdd"), 2)
	_text(status, rect.position + Vector2(9, 16), 13, PAPER)


func _bottom_bar(w: float, h: float) -> void:
	var x := w * 0.5 - 346
	var y := h - 132
	_panel(Rect2(x, y, 692, 104), Color("#11151cf5"), 12)
	_panel(Rect2(x + 13, y + 13, 70, 78), Color("#242b36"), 8)
	_center(str(game.player.shirt_number), Vector2(x + 48, y + 53), 32, LIME, true)
	_center("YOU", Vector2(x + 48, y + 76), 11, PAPER, true)
	var status := "无球跑动"
	if game.carrier == game.player:
		status = "正在控球"
	elif game.carrier != null:
		status = "队友控球" if game.carrier.team == game.player.team else "对方控球"
	_text(status, Vector2(x + 99, y + 35), 16, PAPER, true)
	var hero_name: String = ("远征者" if game.player.w_unlocked else "白板") if game.mode == "rogue" else Roles.NAMES[game.player.archetype]
	_text(hero_name + " / " + Formations.LINE_NAMES[game.player.tactical_line], Vector2(x + 99, y + 57), 12, Roles.COLORS[game.player.archetype])
	var passive := "→  进攻方向" if game.player.team == 0 else "←  进攻方向"
	if game.player.archetype == Roles.Kind.STRIKER:
		passive = "移动施法 · 眩晕 1s"
	if game.player.archetype == Roles.Kind.WARDEN:
		passive = "己半场 +10%" if game.player.position.x * (1 if game.player.team == 0 else -1) <= 0 else "敌半场 -15%"
	if game.mode == "rogue":
		passive = "无英雄被动 · 天赋成长"
	_text(passive, Vector2(x + 99, y + 80), 12, LIME)
	_skill(Rect2(x + 230, y + 13, 132, 78), "Q", "手扑 / 出球" if game.player.goalkeeper else "向前踢球", game.player.kick_cooldown, Roles.SAVE_COOLDOWN if game.player.goalkeeper else game.KICK_COOLDOWN, false)
	var kind: int = game.player.archetype
	var cooldown: float = game.player.ability_cooldown
	var ready: bool = cooldown <= 0
	var label := ""
	if game.player.charging:
		label = "%d%% · 松开 W" % roundi(game.player.charge_fraction() * 100)
	elif game.player.stun_time > 0.0:
		label = "眩晕 %.1fs" % game.player.stun_time
	elif game.player.throw_windup > 0.0:
		label = "投掷前摇"
	elif game.player.dash_remaining > 0:
		label = "冲刺中"
	elif game.player.ability_time > 0:
		label = "生效 %.1fs" % game.player.ability_time
	elif kind == Roles.Kind.CHARGER and ready:
		label = "长按 W 蓄力"
	elif kind in [Roles.Kind.STRIKER, Roles.Kind.WARDEN] and ready:
		label = "鼠标放置领域" if kind == Roles.Kind.WARDEN else "朝鼠标投掷"
	if not game.player.w_unlocked:
		label = "胜利后学习"
		ready = false
		cooldown = game.player.ability_max_cooldown()
	_skill(Rect2(x + 374, y + 13, 140, 78), "W", Roles.W_NAMES[kind] if game.player.w_unlocked else "尚未学习", cooldown, game.player.ability_max_cooldown(), ready, label)
	if game.player.charging:
		draw_rect(Rect2(x + 384, y + 77, 120, 4), INK)
		draw_rect(Rect2(x + 384, y + 77, 120 * game.player.charge_fraction(), 4), Roles.COLORS[kind])
	var e_id: int = game.player.e_selected
	var e_count: int = game.player.e_charges.get(e_id, 0)
	var e_title: String = ESkills.SKILLS[e_id].name if e_id >= 0 else "购买技能"
	var e_cd: float = ESkills.SKILLS[e_id].cooldown if e_id >= 0 else 1.0
	var e_label := "剩余 %d 次" % e_count if game.player.e_cooldown <= 0.0 else "%.1fs · %d 次" % [game.player.e_cooldown, e_count]
	if game.mode == "rogue":
		e_title = ESkills.SKILLS[e_id].name if e_id >= 0 else "尚未学习"
		e_count = 1 if game.player.e_unlimited else 0
		e_cd = game.rogue.E_COOLDOWNS[e_id] / (1.0 + game.player.equipment_bonus("haste")) if e_id >= 0 else 1.0
		e_label = ("常驻 · 就绪" if game.player.e_cooldown <= 0 else "冷却 %.1fs" % game.player.e_cooldown) if e_id >= 0 else "胜利后学习"
	_skill(Rect2(x + 526, y + 13, 152, 78), "E", e_title, game.player.e_cooldown if e_count > 0 else e_cd, e_cd, false, e_label)
	_center("右键移动   ·   左键转向   ·   Q 沿箭头方向踢球", Vector2(w * 0.5, y - 18), 13, PAPER)


func _skill(rect: Rect2, key: String, title: String, cooldown: float, maximum: float, active: bool, custom_label: String = "") -> void:
	var ready := cooldown <= 0 or active
	_panel(rect, Color("#252c36") if ready else Color("#1a1f28"), 7)
	_panel(Rect2(rect.position + Vector2(9, 9), Vector2(30, 30)), LIME if ready or active else Color("#58616d"), 5)
	_center(key, rect.position + Vector2(24, 31), 18, INK, true)
	_text(title, rect.position + Vector2(47, 29), 14, PAPER, true)
	var label := "就绪" if ready else "%.1fs" % cooldown
	if not custom_label.is_empty():
		label = custom_label
	_text(label, rect.position + Vector2(47, 49), 12, LIME if ready or active else MUTED)
	var bar := Rect2(rect.position + Vector2(10, 64), Vector2(rect.size.x - 20, 4))
	draw_rect(bar, Color("#0a0d12"))
	bar.size.x *= clampf(1.0 - cooldown / maximum, 0.0, 1.0)
	draw_rect(bar, LIME if ready or active else Color("#abb4c3"))


func _wallet(w: float) -> void:
	if game.mode == "rogue":
		_panel(Rect2(w - 280, 86, 252, 72), Color("#11151ce8"), 2)
		_text("%d 人阵容  /  %d 种天赋" % [game.rogue.members.size() + 2, game.rogue.talent_kind_count()], Vector2(w - 264, 114), 16, PAPER, true)
		_text("H 构筑 · 天赋含 W/E 与顶级", Vector2(w - 264, 141), 12, LIME)
		return
	_panel(Rect2(w - 280, 86, 252, 142), Color("#11151ce8"), 2)
	_text("%d 金" % game.player.gold, Vector2(w - 264, 114), 21, PAPER, true)
	_text("装备 %d / %d" % [game.player.inventory.size(), Gear.SLOTS], Vector2(w - 128, 112), 12, MUTED)
	for slot in range(Gear.SLOTS):
		var label: String = Gear.ITEMS[game.player.inventory[slot]].name if slot < game.player.inventory.size() else "—"
		_text(label, Vector2(w - 262 + (slot % 2) * 119, 143 + (slot / 2) * 23), 12, PAPER if slot < game.player.inventory.size() else MUTED)
	_text("队速 ×%.3f · 进化 %d / 虚弱 %d" % [game.team_speed(game.player.team), game.team_upgrades[game.player.team][0], game.team_upgrades[1 - game.player.team][1]], Vector2(w - 264, 213), 11, MUTED)
	if game.money_message_time > 0:
		_text(game.money_message, Vector2(w - 264, 249), 13, LIME)


func shop_items() -> Array[int]:
	if shop_tab == 2:
		return []
	return Gear.visible_items(game.player.archetype, 2 if shop_tab == 3 else shop_tab)


func shop_card_rect(slot: int) -> Rect2:
	return Rect2(size.x * 0.5 - 584 + (slot % 4) * 295, size.y * 0.5 - 156 + (slot / 4) * 168, 283, 156)


func shop_tab_rect(index: int) -> Rect2:
	return Rect2(size.x * 0.5 - 584 + index * 180, size.y * 0.5 - 195, 168, 30)


func shop_item_rect(item_id: int) -> Rect2:
	var slot := shop_items().find(item_id)
	return shop_card_rect(slot) if slot >= 0 else Rect2()


func shop_item_at(point: Vector2) -> int:
	for item_id in shop_items():
		if shop_item_rect(item_id).has_point(point):
			return item_id
	return -1


func shop_e_rect(skill_id: int) -> Rect2:
	var slot := ESkills.visible_skills(game.player.archetype).find(skill_id)
	return shop_card_rect(slot) if slot >= 0 else Rect2()


func shop_click(point: Vector2) -> bool:
	for index in range(4):
		if shop_tab_rect(index).has_point(point):
			shop_tab = index
			return true
	if shop_tab != 2:
		return false
	for id in ESkills.visible_skills(game.player.archetype):
		var rect := shop_e_rect(id)
		if not rect.has_point(point):
			continue
		if point.y >= rect.position.y + 115:
			var reason: String = game.e_purchase_error(game.player, id)
			game.shop_feedback = "已购买「%s」1 次并装备" % ESkills.SKILLS[id].name if game.buy_e(game.player, id) else reason
		else:
			game.shop_feedback = "已装备「%s」· 次数分别保存" % ESkills.SKILLS[id].name if game.equip_e(game.player, id) else "先购买次数，再点击卡片切换"
		return true
	return false


func inventory_slot_rect(slot: int) -> Rect2:
	return Rect2(size.x * 0.5 - 584 + slot * 197, size.y * 0.5 + 212, 185, 54)


func inventory_slot_at(point: Vector2) -> int:
	for slot in range(Gear.SLOTS):
		if inventory_slot_rect(slot).has_point(point):
			return slot
	return -1


func formation_rect(index: int) -> Rect2:
	var y := size.y * 0.5 - 282 if game.shop_open else size.y * 0.5 + 110
	return Rect2(size.x * 0.5 - 584 + index * 157, y, 145, 46)


func formation_at(point: Vector2) -> int:
	for i in range(Formations.NAMES.size()):
		if formation_rect(i).has_point(point):
			return i
	return -1


func _formations_row() -> void:
	for i in range(Formations.NAMES.size()):
		var rect := formation_rect(i)
		var selected: bool = game.team_formations[game.player.team] == i
		_panel(rect, LIME if selected else Color("#252c36"), 6)
		_center(Formations.NAMES[i], rect.position + Vector2(72, 21), 18, INK if selected else PAPER, true)
		_center(Formations.STYLES[i], rect.position + Vector2(72, 38), 11, INK if selected else MUTED)
	var text_pos := formation_rect(0).position + Vector2(804, 17)
	if game.started:
		_text("对手  %s · %s" % [Formations.NAMES[game.team_formations[1 - game.player.team]], Formations.STYLES[game.team_formations[1 - game.player.team]]], text_pos, 14, CORAL, true)
		_text("点击换阵 · 续赛后跑位 · 保留角色和装备", text_pos + Vector2(0, 21), 12, MUTED)
	else:
		_text("优先：疾风 / 月影前场 · 刺猬中场", text_pos, 13, PAPER)
		_text("旗帜 / 镇域后场 · 铁闸门将 · 允许少量混编", text_pos + Vector2(0, 21), 12, MUTED)


func _shop(w: float, h: float) -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color("#080b11c9"))
	var origin := Vector2(w * 0.5 - 610, h * 0.5 - 380)
	_panel(Rect2(origin, Vector2(1220, 760)), Color("#11151cfc"), 16)
	_text(game.shop_title + "  /  球场装备站", origin + Vector2(26, 45), 26, PAPER, true)
	var countdown := "购买计时已暂停 · Esc 继续" if game.paused else "比赛计时暂停 · %d 秒后%s" % [int(ceil(game.goal_pause)), "原地续赛" if game.supply_shop else "自动开球"]
	if game.timeout_team >= 0:
		countdown = "战术暂停 %ds · %s中线开球 · 双方均可购买" % [ceili(game.goal_pause), "蓝队" if game.timeout_team == 0 else "红队"]
	if game.net != null:
		countdown += " · 已准备 %d/%d" % [game.net.shop_ready.size(), game.net.members.size()]
	if game.is_practice():
		countdown = "练习商店不限时 · Enter 返回球场 · B 可重新打开"
	_text(countdown, origin + Vector2(26, 78), 15, MUTED)
	if game.is_practice():
		_text("自由试装 · 金币与技能次数只在练习中有效", origin + Vector2(26, 128), 18, LIME)
	else:
		_formations_row()
	_text("6 格装备 · 小件可重复 / 成装限一 · 原价抵扣材料 · 出售返还总价 70%", origin + Vector2(26, 170), 13, MUTED)
	_center("%d 金" % game.player.gold, origin + Vector2(1062, 48), 30, LIME, true)
	_center("E 次数独立保存，不占装备格", origin + Vector2(1062, 79), 13, MUTED)
	for i in range(4):
		var tab := shop_tab_rect(i)
		_panel(tab, LIME if shop_tab == i else Color("#252c36"), 5)
		_center(["小件 / 起步", "成装 / 合成", "E / 技能次数", "全队升级"][i], tab.get_center() + Vector2(0, 5), 14, INK if shop_tab == i else PAPER, true)
	_text("Enter 准备 · 双方准备后继续" if game.net != null else ("Enter 结束暂停 · 中线重新开球" if game.timeout_team >= 0 else "Enter 继续比赛 · Esc 暂停阅读"), origin + Vector2(856, 205), 14, LIME)
	for item_id in shop_items():
		var item: Dictionary = Gear.ITEMS[item_id]
		var rect := shop_item_rect(item_id)
		var reason: String = game.purchase_error(game.player, item_id)
		var accent: Color = Roles.COLORS[item.role] if item.role >= 0 else BLUE
		_panel(rect, Color("#30372a") if item_id in game.player.inventory else Color("#202630"), 8)
		draw_rect(Rect2(rect.position, Vector2(3, rect.size.y)), accent)
		_text(item.name, rect.position + Vector2(12, 27), 20, PAPER, true)
		_text(item.tag, rect.position + Vector2(157, 25), 11, accent)
		_text(item.lines[0], rect.position + Vector2(12, 52), 13, PAPER)
		_text(item.lines[1], rect.position + Vector2(12, 73), 12, MUTED)
		var recipe := "总价 %d 金" % item.cost
		if not item.recipe.is_empty():
			var names: PackedStringArray = []
			for component in item.recipe:
				names.append(Gear.ITEMS[component].name)
			recipe = " + ".join(names) + " · 总价 %d" % item.cost
		_text(recipe, rect.position + Vector2(12, 98), 11, accent)
		var button := Rect2(rect.position + Vector2(10, 115), Vector2(263, 31))
		_panel(button, LIME if reason.is_empty() else Color("#313944"), 5)
		var cost := Gear.buy_cost(game.player.inventory, item_id)
		var label := ("合成 / 补齐 %d 金" if item.tier == 1 else "购买 %d 金") % cost if reason.is_empty() else "%d 金 · %s" % [cost, reason]
		_center(label, button.get_center() + Vector2(0, 5), 13, INK if reason.is_empty() else MUTED, true)
	if shop_tab == 2:
		_draw_e_shop(origin)
	elif shop_tab == 3:
		_text("全队升级不占格，本场永久；每队每项最多 %d 次，所有队员共享。" % Gear.TEAM_UPGRADE_CAP, origin + Vector2(26, 428), 18, PAPER)
		_text("NPC 先出齐六件成装。本队已购：进化 %d/%d · 虚弱 %d/%d" % [game.team_upgrades[game.player.team][0], Gear.TEAM_UPGRADE_CAP, game.team_upgrades[game.player.team][1], Gear.TEAM_UPGRADE_CAP], origin + Vector2(26, 465), 15, MUTED)
		_text("蓝队移速 ×%.3f    /    珊瑚队移速 ×%.3f" % [game.team_speed(0), game.team_speed(1)], origin + Vector2(26, 505), 18, LIME)
	_text("装备 %d / 6" % game.player.inventory.size(), origin + Vector2(26, 577), 15, PAPER, true)
	_text(game.shop_feedback, origin + Vector2(170, 577), 13, LIME)
	for slot in range(Gear.SLOTS):
		var rect := inventory_slot_rect(slot)
		_panel(rect, Color("#242a34"), 7)
		if slot < game.player.inventory.size():
			var id: int = game.player.inventory[slot]
			_text(Gear.ITEMS[id].name, rect.position + Vector2(10, 23), 15, PAPER, true)
			_text("点击出售 +%d 金" % Gear.sell_price(id), rect.position + Vector2(10, 43), 12, CORAL)
		else:
			_center("空装备格", rect.get_center() + Vector2(0, 5), 14, MUTED)
	var actor = game.player
	_text("当前：%s · 移速 %.2f m/s · W 冷却 %.1fs · 判定 ×%.2f · 踢球 ×%.2f · 抗减速 %d%%" % [Formations.LINE_NAMES[actor.tactical_line], actor.move_speed(), actor.ability_max_cooldown(), actor.hit_scale(), 1.0 + actor.equipment_bonus("kick"), roundi(actor.slow_resistance() * 100)], origin + Vector2(26, 681), 14, PAPER)
	_text("下次进球赏金：蓝队 ×%.2f / 珊瑚队 ×%.2f · 购买 E 后自动装备，卡片上半部可切换" % [game.comeback_multiplier(0), game.comeback_multiplier(1)], origin + Vector2(26, 710), 14, LIME)
	_text("材料会在合成时消耗，不会重复叠加属性；满格时仍可通过消耗材料合成。", origin + Vector2(26, 738), 12, MUTED)


func _draw_e_shop(origin: Vector2) -> void:
	for id in ESkills.visible_skills(game.player.archetype):
		var skill: Dictionary = ESkills.SKILLS[id]
		var rect := shop_e_rect(id)
		var selected: bool = game.player.e_selected == id
		var count: int = game.player.e_charges.get(id, 0)
		_panel(rect, Color("#30372a") if selected else Color("#202630"), 8)
		_text(skill.name + (" · 已装备" if selected else ""), rect.position + Vector2(12, 27), 20, LIME if selected else PAPER, true)
		_text(skill.lines[0], rect.position + Vector2(12, 53), 13, PAPER)
		_text(skill.lines[1], rect.position + Vector2(12, 75), 12, MUTED)
		_text("%s · 余 %d 次 · CD %ds" % ["专属" if skill.role >= 0 else "通用", count, skill.cooldown], rect.position + Vector2(12, 99), 13, BLUE)
		var reason: String = game.e_purchase_error(game.player, id)
		var button := Rect2(rect.position + Vector2(10, 115), Vector2(263, 31))
		_panel(button, LIME if reason.is_empty() else Color("#313944"), 5)
		_center("买 1 次 · %d 金" % skill.cost if reason.is_empty() else reason, button.get_center() + Vector2(0, 5), 13, INK if reason.is_empty() else MUTED, true)
	_text("按 E 释放当前技能 · 成功释放才消耗 1 次", origin + Vector2(26, 428), 20, PAPER, true)
	_text("购买按钮：增加次数并装备    /    点击卡片上半部：装备已购买的技能", origin + Vector2(26, 468), 15, MUTED)
	_text("进球与换阵保留次数、E 冷却；重开比赛清零。次数不可出售。", origin + Vector2(26, 501), 15, MUTED)
	_text("E 冷却独立于 W 急速；切换技能不会清除冷却。", origin + Vector2(26, 534), 15, LIME)


func _controls(h: float) -> void:
	_panel(Rect2(28, h - 117, 244, 89), Color("#11151cbf"), 2)
	_text("Space 回到球员   Tab 全场", Vector2(43, h - 91), 12, PAPER)
	_text("滚轮 缩放   Y 锁定 / 自由镜头", Vector2(43, h - 67), 12, MUTED)
	_text("H 操作说明   Esc 菜单" if game.net != null else "H 操作说明   Esc 暂停", Vector2(43, h - 43), 12, MUTED)


func _minimap(rect: Rect2) -> void:
	_panel(rect, Color("#11151ce8"), 9)
	_text("全场态势", rect.position + Vector2(13, 23), 12, MUTED)
	var pitch := Rect2(rect.position + Vector2(13, 35), rect.size - Vector2(26, 48))
	draw_rect(pitch, Color("#272e35"))
	draw_rect(pitch, Color("#727c89"), false, 1)
	draw_line(Vector2(pitch.get_center().x, pitch.position.y), Vector2(pitch.get_center().x, pitch.end.y), Color("#727c89"))
	draw_arc(pitch.get_center(), 13, 0, TAU, 32, Color("#727c89"))
	for actor in game.players:
		var at := _map_point(actor.position, pitch)
		if actor.human:
			draw_arc(at, 5.5, 0, TAU, 16, LIME, 1.5)
		draw_circle(at, 2.7, BLUE if actor.team == 0 else CORAL)
	draw_circle(_map_point(game.ball.position, pitch), 2.5, PAPER)
	var focus := _map_point(game.camera_focus, pitch)
	var view_size := Vector2(game.camera.size * 1.4 / 96 * pitch.size.x, game.camera.size / 60 * pitch.size.y)
	draw_rect(Rect2(focus - view_size * 0.5, view_size).intersection(pitch), Color("#e0e7f165"), false, 1)


func _map_point(at: Vector3, rect: Rect2) -> Vector2:
	return rect.position + Vector2((at.x + 48) / 96, (at.z + 30) / 60) * rect.size


func _start_screen(w: float, h: float) -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color("#070a0f88"))
	var origin := Vector2(w * 0.5 - 610, h * 0.5 - 380)
	_panel(Rect2(origin, Vector2(1220, 760)), Color("#11151cf5"), 16)
	draw_rect(Rect2(origin + Vector2(32, 31), Vector2(40, 3)), LIME)
	_text("赛前准备", origin + Vector2(87, 38), 12, LIME, true)
	_text("训练场 · 选择英雄" if game.mode == "training" else ("征服 · 选择英雄" if game.mode == "conquest" else "自由模式 · 选择英雄"), origin + Vector2(30, 85), 32, PAPER, true)
	_text("右键移动 · Q / W / E · 商店购买 E 次数", origin + Vector2(700, 81), 14, MUTED)
	_settings_row()
	for i in range(Roles.NAMES.size()):
		var rect := role_card_rect(i)
		var selected: bool = game.selected_role == i
		var locked: bool = game.mode == "conquest" and game.Modes.CHALLENGES[game.challenge_id].role >= 0 and game.Modes.CHALLENGES[game.challenge_id].role != i
		var color: Color = Roles.COLORS[i]
		if locked:
			color = color.darkened(0.55)
		_panel(rect, Color("#30372a") if selected else Color("#1b2029"), 9)
		if selected:
			draw_rect(Rect2(rect.position, Vector2(rect.size.x, 3)), color)
		_text("0%d" % (i + 1), rect.position + Vector2(17, 29), 14, color, true)
		_role_icon(i, rect.position + Vector2(92, 65), color)
		_text(Roles.NAMES[i], rect.position + Vector2(18, 126), 25, MUTED if locked else PAPER, true)
		_text("本关锁定" if locked else ("已选择" if selected else "按 %d 选择" % (i + 1)), rect.position + Vector2(116, 124), 11, color)
		_text("己半场 +10% / 敌半场 -15%" if i == Roles.Kind.WARDEN else Roles.PASSIVES[i], rect.position + Vector2(10, 155), 10, MUTED)
		_text("W  " + Roles.W_NAMES[i], rect.position + Vector2(18, 185), 16, color, true)
		var details: PackedStringArray = Roles.W_DETAILS[i].split(" / ")
		_text(details[0], rect.position + Vector2(10, 211), 10, PAPER)
		_text(details[1], rect.position + Vector2(18, 234), 12, color)
		if i == Roles.Kind.STRIKER:
			_text("移动施法 · 固定眩晕 1 秒", rect.position + Vector2(10, 255), 10, MUTED)
		elif i == Roles.Kind.KEEPER:
			_text("接管蓝队 1 号 · 仅限自家禁区", rect.position + Vector2(10, 255), 10, MUTED)
	if game.mode != "training":
		_formations_row()
	_center("F1 回球 · F2 复位 · F3 刷新技能与资源 · B 试装 · 门将 F4 来球" if game.mode == "training" else "初始按位置倾向随机英雄；商店可换阵，保留球员成长与装备", origin + Vector2(610, 561), 13, MUTED)
	_panel(Rect2(origin + Vector2(24, 578), Vector2(1172, 53)), LIME, 7)
	var start_label := "「%s」 · %s · %d 分钟 · 队友%s / 对手%s    →" % [Roles.NAMES[game.selected_role], Formations.NAMES[game.team_formations[game.player.team]], game.match_minutes, Settings.NAMES[game.ai_difficulty(game.player.team)], Settings.NAMES[game.ai_difficulty(1 - game.player.team)]]
	if game.mode == "conquest":
		start_label = "「%s」 · %s · %d 秒 · %s AI    →" % [Roles.NAMES[game.selected_role], game.Modes.CHALLENGES[game.challenge_id].title, game.regulation_duration, Settings.NAMES[game.difficulty]]
	elif game.mode == "training":
		start_label = "「%s」 · 进入训练场    →" % Roles.NAMES[game.selected_role]
	_center(start_label, origin + Vector2(610, 613), 20, INK, true)
	_center("Enter 开始 / R 重开 / 上方按钮返回主界面" if game.mode != "free" else "Enter 开始 / 平局追加完整 2 分钟，直到分出胜负 / R 重开保留时长和难度", origin + Vector2(610, 702), 12, MUTED)


func duration_rect(increase: bool) -> Rect2:
	return Rect2(size.x * 0.5 - 478 + (132 if increase else 0), size.y * 0.5 - 260, 40, 34)


func difficulty_rect(index: int, allied: bool = false) -> Rect2:
	return Rect2(size.x * 0.5 - 100 + index * 150, size.y * 0.5 - 260 + (38 if allied else 0), 136, 34)


func settings_click(point: Vector2) -> bool:
	for increase in [false, true]:
		if duration_rect(increase).has_point(point):
			game.choose_minutes(game.match_minutes + (1 if increase else -1))
			return true
	for index in range(3):
		if difficulty_rect(index).has_point(point):
			game.choose_difficulty(index)
			return true
		if difficulty_rect(index, true).has_point(point):
			game.choose_ally_difficulty(index)
			return true
	return false


func _settings_row() -> void:
	var origin := Vector2(size.x * 0.5 - 584, size.y * 0.5 - 260)
	if game.mode == "conquest":
		var rules: Dictionary = game.Modes.CHALLENGES[game.challenge_id]
		_text("%s · %d 秒 · %s AI · %d 对 11" % [rules.title, rules.seconds, Settings.NAMES[rules.difficulty], rules.team_size], origin + Vector2(0, 23), 19, LIME, true)
		_text(" / ".join(rules.brief) + (" · 本关限定铁闸" if rules.role == 4 else ""), origin + Vector2(0, 59), 14, MUTED)
		return
	if game.mode == "training":
		_text("无限时间 · 自由试装 · 按 1–6 随时更换英雄", origin + Vector2(0, 23), 19, LIME, true)
		_text("使用同一套足球、技能与装备规则，练习资源只在训练场生效。", origin + Vector2(0, 59), 14, MUTED)
		return
	_text("比赛时长", origin + Vector2(0, 23), 16, PAPER, true)
	for increase in [false, true]:
		var rect := duration_rect(increase)
		_panel(rect, Color("#2a313c"), 5)
		_center("+" if increase else "−", rect.get_center() + Vector2(0, 6), 23, LIME, true)
	_center("%d 分钟" % game.match_minutes, origin + Vector2(192, 23), 17, LIME, true)
	_text("5–15 分钟，每次调整 1 分钟", origin + Vector2(0, 59), 12, MUTED)
	for allied in [false, true]:
		_text("队友难度" if allied else "对手难度", origin + Vector2(370, 61 if allied else 23), 16, BLUE if allied else CORAL, true)
		for index in range(3):
			var rect := difficulty_rect(index, allied)
			var selected: bool = (game.ally_difficulty if allied else game.difficulty) == index
			_panel(rect, LIME if selected else Color("#252c36"), 5)
			_center(Settings.NAMES[index], rect.get_center() + Vector2(0, 6), 17, INK if selected else PAPER, true)


func role_card_rect(kind: int) -> Rect2:
	return Rect2(size.x * 0.5 - 584 + kind * 197, size.y * 0.5 - 185, 185, 270)


func role_card_at(point: Vector2) -> int:
	for i in range(Roles.NAMES.size()):
		if role_card_rect(i).has_point(point):
			return i
	return -1


func _role_icon(kind: int, at: Vector2, color: Color) -> void:
	# A squad shirt replaces the fantasy badge; the armband carries the role colour.
	var outline := PackedVector2Array([
		at + Vector2(-17, -30), at + Vector2(-38, -17), at + Vector2(-28, 1),
		at + Vector2(-20, -4), at + Vector2(-20, 34), at + Vector2(20, 34),
		at + Vector2(20, -4), at + Vector2(28, 1), at + Vector2(38, -17),
		at + Vector2(17, -30), at + Vector2(9, -25), at + Vector2(-9, -25)])
	draw_colored_polygon(outline, Color("#eac944") if kind == Roles.Kind.KEEPER else Color("#1973d6"))
	draw_line(at + Vector2(-34, -13), at + Vector2(-27, -2), color, 5, true)
	draw_arc(at + Vector2(0, -33), 12, 0, PI, 20, PAPER, 2, true)
	_center(str(kind + 1), at + Vector2(0, 17), 26, PAPER, true)


func _help_panel(w: float, h: float) -> void:
	var is_rogue: bool = game.mode == "rogue"
	var panel_size := Vector2(1080, 620) if is_rogue else Vector2(550, 398)
	var x := (w - panel_size.x) * 0.5
	var y := (h - panel_size.y) * 0.5
	_panel(Rect2(Vector2(x, y), panel_size), Color("#11151cf5"), 2)
	_text("操作手册", Vector2(x + 26, y + 42), 25, PAPER, true)
	var lines := [
		"鼠标右键 / 按住右键     移动，接近足球自动带球",
		"鼠标左键     原地转向，脚下箭头就是射门方向",
		"Q     门将：无球扑救 / 有球向前出球；其他人踢球",
		"E     商店购买次数；一次装备一种，按 E 使用",
		"W     " + Roles.NAMES[game.player.archetype] + "：" + Roles.W_DETAILS[game.player.archetype],
		"S 停止移动 · M 音乐/音效开关",
		"Space 回中 · Y 自由镜头（屏幕边缘平移）",
		"滚轮缩放 · Tab 全场 · Esc 暂停 · R 重开",
		"W 镇域鼠标放置 / 旗帜投掷 · 门将随朝向"
	]
	if game.player.archetype == Roles.Kind.STRIKER:
		lines[7] = "命中 %d · W 宽 %.2fm / 弹速 %.1f / 眩晕 %.1fs" % [game.player.stats.stuns, game.player.throw_radius() * 2.0, game.player.throw_speed(), game.player.throw_stun()]
	if game.net != null:
		lines[7] = "滚轮缩放 · Tab 全场 · Esc 本地菜单（比赛不停）"
		lines[8] = "P 控球暂停 · Enter 准备 · 暂停方中线开球"
	elif game.mode in ["free", "conquest"]:
		lines[8] = "P 控球暂停 · 每 90 秒 +1 次，上限 2 · Enter 继续"
	if game.mode == "rogue":
		lines[3] = "E     天赋学习后常驻，冷却结束可再次使用"
		if game.player.e_selected >= 0:
			lines[3] = "E     " + game.rogue.e_detail(game.rogue.e_quality, game.player.e_selected) + " · 无限次"
		lines[4] = "W     " + (Roles.W_DETAILS[game.player.archetype] if game.player.w_unlocked else "尚未学习；胜利后选择技能天赋")
		lines[7] = "滚轮缩放 · Tab 全场 · Esc 暂停 · 不能重开本关"
	for i in range(lines.size()):
		_text(lines[i], Vector2(x + 26, y + 83 + i * 29), 13, MUTED if i == 7 else PAPER)
	if is_rogue:
		draw_line(Vector2(x + 568, y + 26), Vector2(x + 568, y + panel_size.y - 26), Color("#ffffff24"))
		_text("本轮构筑", Vector2(x + 596, y + 42), 25, PAPER, true)
		var build: Array = game.rogue.build_lines()
		for i in range(build.size()):
			_text(build[i], Vector2(x + 596, y + 80 + i * 23), 14, LIME if str(build[i]).begins_with("顶级") else PAPER)
		var enemy: Dictionary = game.rogue.enemy_bonuses()
		_text("本关对手强化", Vector2(x + 26, y + 431), 18, CORAL, true)
		_text("移速 +%.1f%% / 踢力 +%.1f%% / 急速 +%.1f%%" % [enemy.speed * 100, enemy.kick * 100, enemy.haste * 100], Vector2(x + 26, y + 462), 13, PAPER)
		_text(game.rogue.quality_text(game.rogue.ascension), Vector2(x + 26, y + 489), 13, MUTED)
		if game.rogue.ascension >= 4:
			_text("休息处必降级一份可选数值天赋；队友、技能与顶级保留。", Vector2(x + 26, y + 516), 13, MUTED)
		if game.rogue.ascension >= 5 and game.rogue.stage == game.rogue.STAGES:
			_text("最终试验 0:1 开局 · 扳平后可金球决胜", Vector2(x + 26, y + 549), 14, CORAL)
			_text("对手额外保护 0.25 秒 / 抗减速 30% / 扑救 0.25 秒", Vector2(x + 26, y + 576), 13, PAPER)
	_text("H 关闭 · 比赛继续 · 领先三球晋级 · 失败可回存档点" if game.mode == "rogue" else ("H 关闭 · 联机中角色固定，不能单独重开" if game.net != null else "H 关闭 · 比赛继续 · Esc 后 1–6 换角重开"), Vector2(x + 26, y + 377), 12, LIME)


func _overlay(w: float, h: float, title: String, subtitle: String, hint: String) -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color("#07090dcc"))
	_panel(Rect2(w * 0.5 - 260, h * 0.5 - 112, 520, 224), Color("#11151cf5"), 12)
	_center(title, Vector2(w * 0.5, h * 0.5 - 46), 36, LIME, true)
	_center(subtitle, Vector2(w * 0.5, h * 0.5 + 7), 21, PAPER)
	_center(hint, Vector2(w * 0.5, h * 0.5 + 67), 15, MUTED)


func _ball_indicator(w: float, h: float) -> void:
	if not game.started or game.paused or game.finished or game.shop_open or game.help_visible:
		return
	var screen: Vector2 = game.camera.unproject_position(game.ball.position)
	var safe := Rect2(48, 156, w - 96, h - 330)
	if safe.has_point(screen):
		# Draw at the ball's real height, above every 3D field/projectile. Physics radius is unchanged.
		var edge: Vector2 = game.camera.unproject_position(game.ball.position + game.camera.global_basis.x * game.Ball.RADIUS)
		var radius := clampf(screen.distance_to(edge), 5.0, 9.0)
		draw_circle(screen, radius + 4.0, Color("#101d25"))
		draw_circle(screen, radius + 2.5, Color("#ffcf58"))
		draw_circle(screen, radius + 1.0, Color("#101d25"))
		draw_circle(screen, radius, Color("#fffdf0"))
		var patch := PackedVector2Array()
		for corner in range(5):
			patch.append(screen + Vector2.UP.rotated(corner * TAU / 5.0) * radius * 0.46)
		draw_colored_polygon(patch, Color("#101d25"))
		var tip := screen + Vector2(0, -radius - 8)
		draw_line(tip + Vector2(-4, -3), tip, Color("#101d25"), 5, true)
		draw_line(tip + Vector2(4, -3), tip, Color("#101d25"), 5, true)
		draw_line(tip + Vector2(-4, -3), tip, Color("#ffcf58"), 2, true)
		draw_line(tip + Vector2(4, -3), tip, Color("#ffcf58"), 2, true)
		return
	var center := Vector2(w * 0.5, h * 0.5)
	var direction := (screen - center).normalized()
	var point := Vector2(clampf(screen.x, safe.position.x, safe.end.x), clampf(screen.y, safe.position.y, safe.end.y))
	draw_circle(point, 17, INK)
	draw_circle(point, 7, PAPER)
	draw_line(point + direction * 22, point + direction * 32, LIME, 3, true)
	_center("BALL", point + Vector2(0, 33), 10, PAPER, true)


func _panel(rect: Rect2, color: Color, radius: int) -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(mini(radius, 2))
	draw_style_box(style, rect)


func _text(value: String, at: Vector2, font_size: int, color: Color, heavy: bool = false) -> void:
	draw_string(bold if heavy else font, at, value, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)


func _center(value: String, at: Vector2, font_size: int, color: Color, heavy: bool = false) -> void:
	var face := bold if heavy else font
	var width := face.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	draw_string(face, at - Vector2(width * 0.5, 0), value, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)
