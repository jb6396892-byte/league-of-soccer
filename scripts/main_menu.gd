extends Control
## Football front end: live stadium, mode list and compact competition screens.
const INK := Color("#0c0e13")
const PANEL := Color("#191d25")
const PAPER := Color("#f2f3f5")
const MUTED := Color("#9ba4b2")
const LIME := Color("#c9ff41")
const CORAL := Color("#ff6f78")
const Modes = preload("res://scripts/game_modes.gd")
const Settings = preload("res://scripts/match_settings.gd")
const Run = preload("res://scripts/rogue_run.gd")
var shell: Node
var font: SystemFont
var display_font: SystemFont
var buttons: Array = []
var focus_index := 0
var chapter := 0
var stadium_view: SubViewport
var shade: GradientTexture2D


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	font = SystemFont.new()
	font.font_names = PackedStringArray(["Microsoft YaHei UI", "Microsoft YaHei", "Segoe UI"])
	display_font = SystemFont.new()
	display_font.font_names = PackedStringArray(["Bahnschrift", "Microsoft YaHei UI"])
	display_font.font_weight = 700

	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.36, 0.66, 1.0])
	gradient.colors = PackedColorArray([Color("#080a0ff5"), Color("#080a0fea"), Color("#080a0f4d"), Color("#080a0f14")])
	shade = GradientTexture2D.new()
	shade.gradient = gradient
	shade.fill_from = Vector2.ZERO
	shade.fill_to = Vector2.RIGHT
	if not shell.simulation_mode:
		stadium_view = preload("res://scripts/menu_stadium.gd").new()
		add_child(stadium_view)


func text_at(value: String, at: Vector2, size_px: int = 16, color: Color = PAPER, bold: bool = false) -> void:
	draw_string(display_font if bold else font, at, value, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px, color)


func panel(rect: Rect2, color: Color, border: Color = Color.TRANSPARENT) -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(2)
	if border.a > 0:
		style.set_border_width_all(1)
		style.border_color = border
	draw_style_box(style, rect)


func button(id: String, rect: Rect2, label: String, subtitle: String = "", primary: bool = false, enabled: bool = true) -> void:
	var active: bool = enabled and focus_index == buttons.size()
	buttons.append({"id": id, "rect": rect, "enabled": enabled})
	panel(rect, LIME if primary and enabled else (Color("#313842") if active else PANEL), LIME if active else Color.TRANSPARENT)
	var color := INK if primary and enabled else (PAPER if enabled else MUTED.darkened(0.25))
	text_at(label, rect.position + Vector2(22, 34), 22 if rect.size.y > 65 else 17, color, true)
	if not subtitle.is_empty():
		text_at(subtitle, rect.position + Vector2(22, 62), 13, INK.lightened(0.15) if primary else MUTED)
	if enabled:
		text_at("→", rect.position + Vector2(rect.size.x - 37, 35), 20, color)


func action_at(point: Vector2) -> String:
	for item in buttons:
		if item.enabled and item.rect.has_point(point):
			return item.id
	return ""


func focus_action() -> String:
	if buttons.is_empty():
		return ""
	return buttons[focus_index].id if buttons[focus_index].enabled else ""


func move_focus(direction: int) -> void:
	for i in range(buttons.size()):
		focus_index = posmod(focus_index + direction, buttons.size())
		if buttons[focus_index].enabled:
			break


func _draw() -> void:
	buttons.clear()
	if shell.page == "session":
		if stadium_view != null:
			stadium_view.active = false
			stadium_view.render_target_update_mode = SubViewport.UPDATE_DISABLED
		_session()
		return
	if stadium_view != null:
		stadium_view.active = true
		stadium_view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		draw_texture_rect(stadium_view.get_texture(), Rect2(Vector2.ZERO, size), false)
	else:
		draw_rect(Rect2(Vector2.ZERO, size), INK)
	if shell.page == "home":
		draw_texture_rect(shade, Rect2(Vector2.ZERO, size), false)
	else:
		draw_rect(Rect2(Vector2.ZERO, size), Color("#0b0e14ec"))
	draw_rect(Rect2(0, 0, size.x, 90), Color("#090c12b8"))
	draw_line(Vector2(64, 90), Vector2(size.x - 64, 90), Color("#ffffff24"), 1)
	text_at("LS", Vector2(64, 58), 30, LIME, true)
	text_at("LEAGUE OF SOCCER", Vector2(118, 56), 21, PAPER, true)
	text_at("smgbro  /  本地球会", Vector2(size.x - 255, 55), 15, PAPER)
	match shell.page:
		"home": _home()
		"conquest": _conquest()
		"credits": _credits()
		"result": _result()
		"rogue_setup": _rogue_setup()
		"rogue_reward": _rogue_reward()
		"rogue_result": _rogue_result()
	if shell.page not in ["home", "online", "online_result"]:
		button("home", Rect2(64, size.y - 88, 212, 48), "返回主界面")
	var footer: String = shell.notice if not shell.notice.is_empty() else "↑ ↓ 选择     Enter 确认     Esc 返回                                      单人模式 / 2 人联机"
	text_at(footer, Vector2(64, size.y - 24), 12, MUTED)
	text_at("M 声音：" + ("关闭" if shell.audio.muted else "开启"), Vector2(size.x - 158, size.y - 24), 12, MUTED)


func _home() -> void:
	text_at("开始比赛", Vector2(64, 155), 34, PAPER, true)
	var entries := [
		["online", "联机比赛", "2 人房间 · 同队合作 / 分队对抗"],
		["free", "自由模式", "11 对 11 · 比赛时间、阵型与难度自选"],
		["conquest", "征服模式", "%d / 15 已完成 · 三个章节" % shell.completed],
		["rogue", "肉鸽远征", "20 关 · 天赋构筑 · 双方困难 AI"],
		["tutorial", "新手教程", "已完成教程" if shell.tutorial_done else "移动、传射、技能与商店"],
		["training", "训练场", "自由练习 · 即时刷新球权和技能"],
		["credits", "开发人员", "制作与鸣谢"],
		["quit", "退出游戏", "返回桌面"]
	]
	for i in range(entries.size()):
		var rect := Rect2(64, 181 + i * 76, 480, 70)
		var active := focus_index == i
		buttons.append({"id": entries[i][0], "rect": rect, "enabled": true})
		if active:
			draw_rect(rect, LIME)
		else:
			draw_line(rect.position + Vector2(0, 70), rect.end, Color("#ffffff18"))
		text_at(entries[i][1], rect.position + Vector2(20, 32), 25, INK if active else PAPER, true)
		text_at(entries[i][2], rect.position + Vector2(20, 57), 13, INK if active else MUTED)
		if active:
			text_at("›", rect.position + Vector2(441, 44), 30, INK, true)
	var info := Rect2(size.x - 625, size.y - 187, 561, 99)
	draw_rect(info, Color("#10151dde"))
	draw_rect(Rect2(info.position, Vector2(3, 99)), LIME)
	text_at("比赛日", info.position + Vector2(24, 31), 15, MUTED)
	text_at("蓝队  /  主场球衣", info.position + Vector2(24, 66), 26, PAPER, true)
	text_at("10", info.position + Vector2(467, 70), 47, PAPER, true)


func _conquest() -> void:
	text_at("征服模式", Vector2(64, 145), 36, PAPER, true)
	text_at("已完成 %d / 15    ·    选择关卡" % shell.completed, Vector2(65, 178), 15, MUTED)
	var chapter_width := (size.x - 160) / 3.0
	for part in range(Modes.CHAPTERS.size()):
		button("chapter:%d" % part, Rect2(64 + part * (chapter_width + 16), 207, chapter_width, 54), Modes.CHAPTERS[part], "", part == chapter)
	var width := size.x - 128
	for slot in range(5):
		var i := chapter * 5 + slot
		var rules: Dictionary = Modes.CHALLENGES[i]
		var done: bool = rules.id in shell.cleared
		var enabled: bool = i <= shell.unlocked_level()
		var row := Vector2(64, 292 + slot * 90)
		draw_rect(Rect2(row, Vector2(width, 84)), Color("#242b35") if enabled and not done else Color("#171c25"))
		text_at("%02d" % (i + 1), row + Vector2(20, 51), 29, LIME if enabled else MUTED, true)
		text_at(rules.title, row + Vector2(88, 34), 22, PAPER, true)
		text_at("%s AI · %d 秒 · %d 对 11" % [Settings.NAMES[rules.difficulty], rules.seconds, rules.team_size], row + Vector2(88, 62), 12, MUTED)
		for j in range(rules.brief.size()):
			text_at(rules.brief[j], row + Vector2(370, 24 + j * 24), 14, PAPER if j == 0 else MUTED)
		button("level:%d" % i, Rect2(row + Vector2(width - 198, 15), Vector2(180, 54)), "再战" if done else ("开赛" if enabled else "未解锁"), "", enabled and not done, enabled)
	text_at("← → 切换章节    ·    完成关卡后解锁下一关    ·    挑战模式不加时", Vector2(66, 777), 14, MUTED)


func _rogue_setup() -> void:
	var level: int = shell.rogue_ascension
	var unlocked: bool = level <= shell.rogue_unlocked
	text_at("肉鸽远征 / 进阶 %d" % level, Vector2(64, 145), 44, PAPER, true)
	var status := "已通关" if level <= shell.rogue_cleared else ("可以挑战" if unlocked else "通关进阶 %d 后解锁" % (level - 1))
	text_at("%s   ·   %s   ·   难度效果累计叠加" % [Run.ASCENSION_NAMES[level], status], Vector2(67, 185), 16, LIME if unlocked else CORAL, true)
	if not shell.rogue_checkpoint.is_empty():
		button("rogue_resume", Rect2(size.x - 404, 99, 336, 56), "继续 A%d · 第 %d 关" % [shell.rogue_checkpoint.ascension, shell.rogue_checkpoint.stage], "", true)
	var step_width := (size.x - 178) / 6.0
	for i in range(6):
		button("ascension:%d" % i, Rect2(64 + i * (step_width + 10), 205, step_width, 48), "%02d · %s" % [i, "已锁" if i > shell.rogue_unlocked else Run.ASCENSION_NAMES[i]], "", i == level)
	for i in range(1, 6):
		text_at("%d  %s" % [i, Run.ASCENSION_RULES[i]], Vector2(67, 281 + (i - 1) * 23), 15, PAPER if i <= level else MUTED.darkened(0.4))
	text_at("白板开局：你 + 两名外场队友 + 门将。W / E 由天赋学习。", Vector2(67, 402), 16, LIME)
	var width := (size.x - 168) / 3.0
	var names := ["前场开局", "中场开局", "后场开局"]
	var hints := ["靠近对方球门，承担终结", "串联攻防，寻找传球线路", "保护门前，发起反击"]
	var teams := ["队友：疾风 + 刺猬", "队友：疾风 + 镇域", "队友：疾风 + 刺猬"]
	for i in range(3):
		var at := Vector2(64 + i * (width + 20), 418)
		panel(Rect2(at, Vector2(width, 216)), PANEL)
		text_at(["FW", "MF", "DF"][i], at + Vector2(24, 37), 22, LIME, true)
		var pitch := Rect2(at + Vector2(width - 121, 12), Vector2(96, 62))
		draw_rect(pitch, Color("#ffffff1c"), false, 1)
		draw_line(pitch.position + Vector2(48, 0), pitch.position + Vector2(48, 62), Color("#ffffff30"), 1)
		draw_arc(pitch.get_center(), 12, 0, TAU, 24, Color("#ffffff30"), 1)
		draw_circle(pitch.position + Vector2([77, 48, 19][i], 31), 5, LIME)
		text_at(names[i], at + Vector2(24, 80), 27, PAPER, true)
		text_at(hints[i], at + Vector2(24, 113), 16, MUTED)
		text_at(teams[i] + " · 门将：铁闸", at + Vector2(24, 143), 14, MUTED)
		button("rogue_start:%d" % (3 - i), Rect2(at + Vector2(16, 160), Vector2(width - 32, 44)), "开始进阶 %d" % level if unlocked else "尚未解锁", "", i == 0, unlocked)
	text_at("双方困难 AI · 90 秒 · 领先三球晋级 · 平局金球加时   /   " + Run.quality_text(level), Vector2(67, 668), 16, PAPER)
	text_at("5 / 10 / 15 关后休息：额外顶级天赋与存档。进阶 4 起必降级一份数值天赋；无目标时跳过。", Vector2(67, 701), 15, MUTED)
	text_at("存档保留进阶与诅咒结果，退出也能继续。开始新远征会替换旧存档。", Vector2(67, 732), 15, MUTED)


func _rogue_route(stage: int) -> void:
	for i in range(20):
		var rect := Rect2(66 + i * ((size.x - 132) / 20.0), 205, (size.x - 132) / 20.0 - 8, 8)
		draw_rect(rect, LIME if i < stage else Color("#353b45"))
	text_at("四人起步", Vector2(67, 245), 14, MUTED)
	text_at("5 / 10 / 15 关 · 存档与顶级天赋", Vector2(size.x * 0.31, 245), 14, LIME)
	text_at("进阶 %d · %s" % [shell.rogue.ascension, "强化最终试验" if shell.rogue.ascension >= 5 else "双方困难 AI"], Vector2(size.x - 330, 245), 14, CORAL)


func _rogue_build(y: float) -> void:
	var lines: Array = shell.rogue.build_lines()
	for i in range(lines.size()):
		text_at(lines[i], Vector2(67 + (i % 4) * ((size.x - 134) / 4.0), y + (i / 4) * 25), 13, MUTED)


func _rogue_reward() -> void:
	text_at(("第 %02d 关存档点 · 选择顶级天赋" if shell.rogue.checkpoint_choice else "第 %02d 关告捷 · 选择天赋") % shell.rogue.stage, Vector2(64, 139), 38, PAPER, true)
	text_at("选定后保存当前阵容与天赋；失败可回到这里，退出后也能继续。" if shell.rogue.checkpoint_choice else ("蓝队 %d : %d 珊瑚队 / " % shell.game.score) + Run.quality_text(shell.rogue.ascension) + " / 三选一", Vector2(67, 180), 16, MUTED)
	_rogue_route(shell.rogue.stage)
	var width := (size.x - 168) / 3.0
	for i in range(3):
		var offer: Dictionary = shell.rogue.offers[i]
		var at := Vector2(64 + i * (width + 20), 276)
		var tint: Color = [Color("#c2d2c8"), Color("#6ac9ff"), Color("#d5a3ff"), Color("#ffd477")][offer.quality]
		panel(Rect2(at, Vector2(width, 295)), PANEL)
		draw_rect(Rect2(at, Vector2(width, 4)), tint)
		text_at(offer.tag, at + Vector2(22, 45), 14, tint)
		text_at(offer.name, at + Vector2(22, 100), 25, PAPER, true)
		var details: PackedStringArray = offer.detail.replace(" / ", "\n").replace("；", "\n").split("\n")
		for row in range(details.size()):
			text_at(details[row], at + Vector2(22, 137 + row * 22), 15, MUTED)
		button("talent:%d" % i, Rect2(at + Vector2(16, 220), Vector2(width - 32, 53)), "选择并存档" if shell.rogue.checkpoint_choice else "选择天赋", "", i == 0)
	text_at(shell.rogue.curse_text() if shell.rogue.checkpoint_choice and shell.rogue.ascension >= 4 else "本轮构筑 · 下一关保留", Vector2(67, 615), 17, CORAL if shell.rogue.checkpoint_choice and shell.rogue.ascension >= 4 else PAPER, true)
	_rogue_build(650)


func _rogue_result() -> void:
	var won: bool = shell.game.result_won
	text_at("远征登顶" if won else "本轮远征结束", Vector2(64, 153), 52, LIME if won else CORAL, true)
	text_at("进阶 %d · " % shell.rogue.ascension + ("战胜第 20 关 · 11 人困难队" if won else "止步第 %02d 关 · 已突破 %d 关" % [shell.rogue.stage, shell.rogue.stage - 1]), Vector2(67, 200), 23, PAPER)
	panel(Rect2(64, 251, size.x - 128, 157), PANEL)
	text_at("蓝队   %d : %d   珊瑚队" % shell.game.score, Vector2(95, 322), 42, PAPER, true)
	var ending := "金球决胜" if shell.game.overtime_count > 0 else "常规终场"
	if won and shell.game.score[0] - shell.game.score[1] >= 3 and shell.game.time_left > 0:
		ending = "领先三球提前晋级"
	text_at("用时 %.1f 秒 · 本关你的进球 %d · %s" % [shell.game.match_elapsed(), shell.game.player.stats.goals, ending], Vector2(97, 374), 17, MUTED)
	text_at("本轮构筑", Vector2(67, 458), 24, PAPER, true)
	_rogue_build(495)
	var next_hint := "回到存档点会恢复当时的构筑与进阶，诅咒不会重抽。"
	if won:
		next_hint = "进阶 5 最终试验已攻克，全部进阶通关！" if shell.rogue.ascension == Run.MAX_ASCENSION else "已解锁进阶 %d，可在新远征中选择。" % mini(Run.MAX_ASCENSION, shell.rogue.ascension + 1)
	text_at(next_hint, Vector2(67, 652), 17, LIME if won else MUTED)
	button("rogue", Rect2(64, 692, 300, 65), "重新出发", "", true)
	if not won and not shell.rogue_checkpoint.is_empty():
		button("rogue_resume", Rect2(390, 692, 370, 65), "回到存档 · 第 %d 关" % shell.rogue_checkpoint.stage, "", true)


func _credits() -> void:
	text_at("开发人员", Vector2(64, 148), 46, PAPER, true)
	text_at("制作与鸣谢", Vector2(67, 187), 15, LIME, true)
	panel(Rect2(64, 230, 560, 470), PANEL)
	text_at("smgbro", Vector2(96, 324), 60, LIME, true)
	text_at("项目作者 · 创意与游戏方向", Vector2(98, 371), 21, PAPER)
	text_at("玩法需求、英雄创意与体验反馈", Vector2(98, 407), 16, MUTED)
	text_at("Codex", Vector2(98, 495), 30, PAPER, true)
	text_at("开发协作 · 实现、调试与迭代支持", Vector2(98, 532), 17, MUTED)
	text_at("感谢每一个愿意再踢一场的玩家。", Vector2(98, 641), 18, CORAL)
	text_at("技术与设计参考", Vector2(686, 277), 27, PAPER, true)
	var lines := ["Godot 4.5.1 · 开源游戏引擎", "EA SPORTS FC · 菜单组织与比赛转播风格", "Rocket League · 自由训练、即时复位", "League of Legends / Dota 2 · 装备与技能思路", "HELIOS / Google Research Football · 足球 AI 参考", "Kenney · CC0 按钮音效；BGM 与进球音为原创", "角色、球场、界面与效果为本项目原创程序绘制。", "未使用上述游戏的角色素材或标识；详细来源见 THIRD_PARTY.md。"]
	for i in range(lines.size()):
		text_at(lines[i], Vector2(686, 329 + i * 39), 15, MUTED)


func _result() -> void:
	var game = shell.game
	var title := "挑战成功" if game.result_won else "挑战未完成"
	if game.mode == "free":
		title = "拿下比赛" if game.result_won else "终场哨响"
	elif game.mode == "tutorial":
		title = "准备好上场了"
	text_at(title, Vector2(100, 210), 62, LIME if game.result_won else CORAL, true)
	var description: String = Modes.CHALLENGES[game.challenge_id].title if game.mode == "conquest" else ("五步教程已完成" if game.mode == "tutorial" else "自由模式")
	text_at(description, Vector2(104, 259), 24, PAPER)
	panel(Rect2(100, 305, size.x - 200, 197), PANEL)
	text_at("蓝队   %d  :  %d   珊瑚队" % game.score, Vector2(140, 389), 48, PAPER, true)
	text_at("有效时间 %.0f 秒    /    你的进球 %d    /    抢断 %d    /    技能使用 %d" % [game.match_elapsed(), game.player.stats.goals, game.player.stats.tackles, game.player.stats.casts + game.player.stats.e_casts], Vector2(143, 455), 17, MUTED)
	if game.mode == "conquest":
		text_at("通关进度已保存" if game.result_won else "目标：" + " · ".join(Modes.CHALLENGES[game.challenge_id].brief), Vector2(104, 552), 17, MUTED)
	button("retry", Rect2(100, 604, 280, 70), "再来一次", "", true)
	if game.mode == "conquest" and game.result_won and game.challenge_id < Modes.CHALLENGES.size() - 1:
		button("next", Rect2(402, 604, 280, 70), "下一关")
	elif game.mode == "tutorial":
		button("free", Rect2(402, 604, 280, 70), "进入自由模式")
	elif game.mode == "conquest" and game.result_won:
		button("conquest", Rect2(402, 604, 280, 70), "查看征服旅程")
		text_at("十五关全部完成 · 球场征服者" if shell.completed == Modes.CHALLENGES.size() else "终章已征服 · 也可以回访未完成关卡", Vector2(104, 719), 23, LIME, true)


func _session() -> void:
	var game = shell.game
	button("home", Rect2(size.x - 201, 24, 177, 42), "离开房间" if game.net != null else "返回主界面")
	if game.net != null:
		text_at("你是%s %d号 · %s" % ["蓝队" if game.player.team == 0 else "红队", game.player.shirt_number, "进攻 →" if game.player.team == 0 else "← 进攻"], Vector2(size.x - 390, 265), 16, LIME)
		if game.net.phase == "loading":
			text_at("正在等待双方加载……", Vector2(550, 170), 24, PAPER)
		if game.net.local_menu:
			panel(Rect2(450, 310, 540, 180), PANEL)
			text_at("菜单已打开，比赛仍在进行", Vector2(480, 365), 27, PAPER, true)
			text_at("Esc 返回比赛 · 右上角离开房间", Vector2(480, 424), 18, MUTED)
		return
	if not game.started or game.shop_open or game.paused or game.help_visible:
		return
	if game.mode == "rogue":
		panel(Rect2(28, 112, 390, 94), Color("#10141cee"))
		text_at("进阶 %d · 远征 %02d / 20 · 双方%s AI" % [shell.rogue.ascension, shell.rogue.stage, Settings.NAMES[game.difficulty]], Vector2(44, 141), 18, LIME, true)
		text_at("金球加时 · 下一球定胜负" if game.overtime_count > 0 else "领先三球晋级 · 90 秒终场 / 平局加时", Vector2(44, 168), 14, PAPER)
		text_at("H 查看构筑与规则 · 5 / 10 / 15 关存档", Vector2(44, 191), 11, MUTED)
	elif game.mode == "conquest":
		panel(Rect2(28, 112, 390, 94), Color("#10141cee"))
		text_at("征服 %d / %d · %s" % [game.challenge_id + 1, Modes.CHALLENGES.size(), Modes.CHALLENGES[game.challenge_id].title], Vector2(44, 141), 18, LIME, true)
		text_at(Modes.CHALLENGES[game.challenge_id].brief[0], Vector2(44, 168), 14, PAPER)
		text_at(Modes.progress_text(game.challenge_id, game.score) + " · 不加时", Vector2(44, 191), 11, MUTED)
	elif game.mode == "tutorial":
		panel(Rect2(24, 165, 430, 174), Color("#10141cee"))
		var lesson: Array = game.Practice.LESSONS[game.practice.step]
		text_at("新手教程  /  %d of 5" % (game.practice.step + 1), Vector2(42, 198), 14, LIME, true)
		text_at(lesson[0], Vector2(42, 240), 25, PAPER, true)
		# Deliberate short lines keep the guidance readable at the game's normal size.
		var message: String = lesson[1]
		text_at(message.substr(0, 23), Vector2(42, 276), 15, MUTED)
		text_at(message.substr(23), Vector2(42, 303), 15, MUTED)
	elif game.mode == "training":
		panel(Rect2(24, 165, 340, 338), Color("#10141cee"))
		text_at("训练场 / 自由实验", Vector2(43, 200), 22, LIME, true)
		text_at("1–6 换英雄 · 静止对手用于测试控制", Vector2(43, 229), 13, MUTED)
		button("ball", Rect2(37, 247, 314, 45), "F1  足球回到脚下")
		button("reset", Rect2(37, 298, 314, 45), "F2  重置场地位置")
		button("refill", Rect2(37, 349, 314, 45), "F3  刷新技能与资源")
		button("shop", Rect2(37, 400, 314, 45), "B    打开试装商店")
		button("shot", Rect2(37, 451, 314, 39), "F4  门将来球训练", "", false, game.player.goalkeeper)
