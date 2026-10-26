extends Control
## Native controls provide editable addresses and standard keyboard focus in the lobby.
var shell: Node
var nickname: LineEdit
var address: LineEdit
var port: SpinBox
var team: OptionButton
var role: OptionButton
var minutes: SpinBox
var difficulty: OptionButton
var status: Label
var roster: Label
var settings_label: Label
var connection: Control
var selection: Control
var ready_button: Button
var start_button: Button
var again_button: Button
var updating := false

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	var theme_resource := Theme.new()
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Microsoft YaHei UI", "Microsoft YaHei", "Segoe UI"])
	theme_resource.default_font = font
	theme_resource.default_font_size = 18
	for kind in ["Button", "OptionButton", "LineEdit"]:
		for state in ["normal", "hover", "pressed", "focus", "disabled"]:
			var style := StyleBoxFlat.new()
			style.bg_color = Color("#303842") if state == "hover" else Color("#191d25")
			style.set_content_margin_all(10)
			if state in ["focus", "pressed"]:
				style.set_border_width_all(2)
				style.border_color = Color("#c9ff41")
			theme_resource.set_stylebox(state, kind, style)
	theme = theme_resource
	_label(self, "联机比赛", Vector2(64, 113), Vector2(700, 56), 36)
	status = _label(self, "", Vector2(66, 178), Vector2(1250, 60), 17)
	connection = Control.new()
	add_child(connection)
	_label(connection, "玩家名", Vector2(66, 252), Vector2(220, 28))
	nickname = LineEdit.new()
	nickname.text = "球员"
	nickname.max_length = 20
	_place(connection, nickname, Rect2(66, 290, 330, 48))
	_label(connection, "房主 IP（局域网或公网地址）", Vector2(66, 360), Vector2(420, 28))
	address = LineEdit.new()
	address.text = "127.0.0.1"
	address.max_length = 253
	_place(connection, address, Rect2(66, 400, 330, 48))
	_label(connection, "UDP 端口", Vector2(66, 468), Vector2(200, 28))
	port = SpinBox.new()
	port.min_value = 1024
	port.max_value = 65535
	port.value = shell.net.PORT
	_place(connection, port, Rect2(66, 505, 330, 48))
	_button(connection, "创建房间", Rect2(66, 590, 155, 52), func(): shell.net.host(nickname.text, int(port.value)))
	_button(connection, "加入房间", Rect2(237, 590, 159, 52), func(): shell.net.join(address.text, nickname.text, int(port.value)))
	_label(connection, "先由一人创建房间，另一人填写房主地址加入。\n\n同一局域网可使用房主的内网 IP。\n跨网络连接需要可达的公网地址和 UDP 端口映射。\n\n首版为 IP 直连，双方须使用相同版本。\n没有自动穿透或房间码服务。", Vector2(510, 265), Vector2(800, 340), 20)
	selection = Control.new()
	add_child(selection)
	_label(selection, "我的球队", Vector2(66, 270), Vector2(310, 28))
	team = OptionButton.new()
	team.add_item("蓝队 · 向右进攻")
	team.add_item("红队 · 向左进攻")
	_place(selection, team, Rect2(66, 310, 330, 48))
	team.item_selected.connect(func(_i): _select())
	_label(selection, "我的角色", Vector2(66, 385), Vector2(310, 28))
	role = OptionButton.new()
	for name in preload("res://scripts/archetypes.gd").NAMES:
		role.add_item(name)
	_place(selection, role, Rect2(66, 425, 330, 48))
	role.item_selected.connect(func(_i): _select())
	ready_button = _button(selection, "准备", Rect2(66, 515, 330, 56), _ready_clicked)
	roster = _label(selection, "", Vector2(510, 267), Vector2(800, 155), 23)
	roster.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	settings_label = _label(selection, "", Vector2(510, 440), Vector2(800, 28), 18)
	minutes = SpinBox.new()
	minutes.min_value = 5
	minutes.max_value = 15
	minutes.suffix = "分钟"
	_place(selection, minutes, Rect2(510, 485, 180, 48))
	minutes.value_changed.connect(func(_v): _configure())
	difficulty = OptionButton.new()
	for label in ["简单 AI", "一般 AI", "困难 AI"]:
		difficulty.add_item(label)
	_place(selection, difficulty, Rect2(716, 485, 190, 48))
	difficulty.item_selected.connect(func(_i): _configure())
	_label(selection, "选择相同球队即为合作，不同球队即为对抗。\n同队只可选择一名门将；更改选项后需要重新准备。", Vector2(510, 565), Vector2(800, 80), 17)
	start_button = _button(selection, "房主开始比赛", Rect2(510, 665, 396, 56), func(): shell.net.start())
	again_button = _button(self, "返回房间，再来一场", Rect2(66, 540, 380, 56), func(): shell.net.back_to_lobby())
	_button(self, "返回主界面 / 离开房间", Rect2(66, 812, 335, 48), func(): shell.leave_session())
	shell.net.changed.connect(refresh)
	refresh()

func _place(parent: Node, item: Control, rect: Rect2) -> void:
	parent.add_child(item)
	item.position = rect.position
	item.size = rect.size

func _label(parent: Node, text: String, at: Vector2, bounds: Vector2, font_size: int = 18) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	_place(parent, label, Rect2(at, bounds))
	return label

func _button(parent: Node, text: String, rect: Rect2, callback: Callable) -> Button:
	var button := Button.new()
	button.text = text
	_place(parent, button, rect)
	button.pressed.connect(callback)
	button.pressed.connect(func(): shell.audio.play_ui())
	button.mouse_entered.connect(func(): shell.audio.play_ui("hover"))
	return button

func _select() -> void:
	if not updating:
		shell.net.select(team.selected, role.selected, false)

func _ready_clicked() -> void:
	var me: Dictionary = shell.net.members[multiplayer.get_unique_id()]
	shell.net.select(team.selected, role.selected, not me.ready)

func _configure() -> void:
	if not updating:
		shell.net.configure(int(minutes.value), difficulty.selected)

func refresh() -> void:
	updating = true
	var net = shell.net
	connection.visible = net.phase in ["offline", "connecting"]
	selection.visible = net.phase == "lobby"
	again_button.visible = net.phase == "result"
	again_button.disabled = not net.hosting
	status.text = net.message
	if net.phase == "result" and shell.game != null:
		var game = shell.game
		status.text = "%s\n蓝队 %d : %d 红队%s" % ["比赛获胜" if game.score[game.player.team] > game.score[1 - game.player.team] else "比赛结束", game.score[0], game.score[1], " · 等待房主返回房间" if not net.hosting else ""]
	if net.phase == "lobby":
		if net.hosting:
			var ips: Array = Array(IP.get_local_addresses()).filter(func(ip): return ip.contains(".") and not ip.begins_with("127.") and not ip.begins_with("169.254."))
			status.text += "\n本机地址：" + " / ".join(ips)
		var me: Dictionary = net.members.get(multiplayer.get_unique_id(), {})
		if not me.is_empty():
			team.select(me.team)
			role.select(me.role)
			ready_button.text = "取消准备" if me.ready else "准备"
		var lines: PackedStringArray = []
		for id in net.members:
			var member: Dictionary = net.members[id]
			lines.append("%s%s  ·  %s / %s  ·  %s" % [member.name, "（房主）" if id == 1 else "", "蓝队" if member.team == 0 else "红队", role.get_item_text(member.role), "已准备" if member.ready else "未准备"])
		roster.text = "\n\n".join(lines)
		minutes.value = net.options.minutes
		minutes.editable = net.hosting
		difficulty.select(net.options.difficulty)
		difficulty.disabled = not net.hosting
		settings_label.text = "比赛设置 · 双方 NPC 使用相同难度（房主修改）"
		start_button.disabled = not net.can_start()
	updating = false
