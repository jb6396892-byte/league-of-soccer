extends RefCounted
## One catalog for shop text, player/NPC purchases and gameplay modifiers.

const START_GOLD := 500
const SLOTS := 6
const SHOP_SECONDS := 15.0
const SUPPLY_SECONDS := 90.0
const TACKLE_GOLD := 50
const INTERCEPT_GOLD := 25
const STUN_GOLD := 20
const DEFENSE_REWARD_COOLDOWN := 6.0
const GOAL_GOLD := 300
const TEAM_GOAL_GOLD := 60
const COMEBACK_PER_GOAL := 0.25
const POSSESSION_SECONDS := 5.0
const POSSESSION_GOLD := 20
const STIPEND_SECONDS := 10.0
const STIPEND_GOLD := 110
const SELL_RATIO := 0.7
const TEAM_BOOTS := 12
const TEAM_SCYTHE := 13
const TEAM_SPEED_GAIN := 1.015
const TEAM_SPEED_LOSS := 0.985
const TEAM_UPGRADE_CAP := 12

# IDs 0..13 stay stable. Components may repeat; completed items are unique.
const ITEMS := [
	{"name": "疾行战靴", "cost": 120, "role": -1, "tag": "小件 · 机动", "tier": 0, "recipe": [], "lines": ["移动速度 +8%", "合成材料 · 可重复购买"], "bonuses": {"speed": 0.08}},
	{"name": "铁壁护胫", "cost": 140, "role": -1, "tag": "小件 · 对抗", "tier": 0, "recipe": [], "lines": ["碰撞及球权判定 +12%", "合成材料 · 可重复购买"], "bonuses": {"size": 0.12}},
	{"name": "重炮鞋钉", "cost": 160, "role": -1, "tag": "小件 · 射门", "tier": 0, "recipe": [], "lines": ["踢球初速度 +15%", "射门、传球均生效"], "bonuses": {"kick": 0.15}},
	{"name": "节奏腕表", "cost": 160, "role": -1, "tag": "小件 · 技能", "tier": 0, "recipe": [], "lines": ["W 技能急速 +25", "单件使 W 冷却 -20%"], "bonuses": {"haste": 0.25}},
	{"name": "吸附球袜", "cost": 120, "role": -1, "tag": "小件 · 接球", "tier": 0, "recipe": [], "lines": ["地面接球范围 +15%", "合成材料 · 可重复购买"], "bonuses": {"pickup": 0.15}},
	{"name": "稳控护符", "cost": 160, "role": -1, "tag": "小件 · 控球", "tier": 0, "recipe": [], "lines": ["得球保护 +0.15 秒", "合成材料 · 可重复购买"], "bonuses": {"protection": 0.15}},
	{"name": "抗阻护带", "cost": 140, "role": -1, "tag": "小件 · 抗减速", "tier": 0, "recipe": [], "lines": ["减速抗性 +40%", "总抗性上限 70%"], "bonuses": {"slow_resist": 0.4}},
	{"name": "超频鞋钉", "cost": 620, "role": 0, "tag": "疾风专属", "tier": 1, "recipe": [0, 3], "lines": ["移速 +8% · W 急速 +25", "W 倍率 1.45 · 持续 2.25s"], "bonuses": {"speed": 0.08, "haste": 0.25, "sprint": 0.1, "duration": 0.25}},
	{"name": "棘刺护甲", "cost": 600, "role": 1, "tag": "刺猬专属", "tier": 1, "recipe": [1, 6], "lines": ["判定 +12% · 抗减速 +40%", "W 半径 6m · 持续 6s"], "bonuses": {"size": 0.12, "slow_resist": 0.4, "radius": 1.5, "duration": 1.0}},
	{"name": "月影核心", "cost": 610, "role": 2, "tag": "月影专属", "tier": 1, "recipe": [0, 5], "lines": ["移速 +8% · 得球保护 +0.15s", "蓄力 0.51s · 最远冲刺 11m"], "bonuses": {"speed": 0.08, "protection": 0.15, "charge": 0.15, "dash": 2.0}},
	{"name": "破阵旗扣", "cost": 600, "role": 3, "tag": "旗帜专属", "tier": 1, "recipe": [2, 3], "lines": ["踢力 +15% · W 急速 +25", "W 弹速 +20% · 射程 +4m"], "bonuses": {"kick": 0.15, "haste": 0.25, "throw_speed": 0.2, "throw_range": 4.0}},
	{"name": "禁区壁垒", "cost": 550, "role": 4, "tag": "铁闸专属", "tier": 1, "recipe": [1, 4], "lines": ["判定 +12% · 接球 +15%", "Q 窗口 +0.45s · W 半径 +2m"], "bonuses": {"size": 0.12, "pickup": 0.15, "save_window": 0.45, "keeper_radius": 2.0}},
	{"name": "进化之靴", "cost": 700, "role": -1, "tag": "全队升级 · 共享上限", "tier": 2, "recipe": [], "lines": ["全队当前移速 ×1.015", "每队最多12次 · 永久 · 不占格"], "bonuses": {}, "team_upgrade": 0},
	{"name": "虚弱之镰", "cost": 700, "role": -1, "tag": "全队升级 · 共享上限", "tier": 2, "recipe": [], "lines": ["对方全队当前移速 ×0.985", "每队最多12次 · 永久 · 不占格"], "bonuses": {}, "team_upgrade": 1},
	{"name": "镇域信标", "cost": 600, "role": 5, "tag": "镇域专属", "tier": 1, "recipe": [3, 6], "lines": ["W 急速 +25 · 抗减速 +40%", "领域半径 +1m · 施法距离 +5m"], "bonuses": {"haste": 0.25, "slow_resist": 0.4, "domain_radius": 1.0, "domain_range": 5.0}},
	{"name": "追猎长靴", "cost": 580, "role": -1, "tag": "成装 · 追球", "tier": 1, "recipe": [0, 4], "lines": ["移动速度 +12%", "地面接球范围 +20%"], "bonuses": {"speed": 0.12, "pickup": 0.2}},
	{"name": "不屈护腿", "cost": 550, "role": -1, "tag": "成装 · 防守", "tier": 1, "recipe": [1, 6], "lines": ["判定 +18% · 抗减速 +35%", "受到的眩晕时长 -20%"], "bonuses": {"size": 0.18, "slow_resist": 0.35, "stun_resist": 0.2}},
	{"name": "破门重炮", "cost": 580, "role": -1, "tag": "成装 · 进攻", "tier": 1, "recipe": [2, 5], "lines": ["踢球初速度 +30%", "得球保护 +0.15 秒"], "bonuses": {"kick": 0.3, "protection": 0.15}},
	{"name": "战术引擎", "cost": 600, "role": -1, "tag": "成装 · 技能", "tier": 1, "recipe": [3, 5], "lines": ["W 技能急速 +40", "得球保护 +0.20 秒"], "bonuses": {"haste": 0.4, "protection": 0.2}},
	{"name": "控球大师", "cost": 620, "role": -1, "tag": "成装 · 控球", "tier": 1, "recipe": [4, 5], "lines": ["地面接球范围 +35%", "得球保护 +0.25 秒"], "bonuses": {"pickup": 0.35, "protection": 0.25}},
	{"name": "反击战甲", "cost": 520, "role": -1, "tag": "成装 · 反击", "tier": 1, "recipe": [1, 0], "lines": ["碰撞及球权判定 +20%", "移动速度 +10%"], "bonuses": {"size": 0.2, "speed": 0.1}},
	{"name": "破阵护符", "cost": 560, "role": -1, "tag": "成装 · 解围", "tier": 1, "recipe": [6, 3], "lines": ["减速抗性 +50%", "W 技能急速 +35"], "bonuses": {"slow_resist": 0.5, "haste": 0.35}}
]
const NPC_BUILDS := [
	[
		[
			7,
			15,
			17,
			19,
			18,
			16
		],
		[
			15,
			7,
			19,
			17,
			16,
			18
		],
		[
			17,
			7,
			21,
			19,
			15,
			18
		]
	],
	[
		[
			8,
			20,
			16,
			18,
			19,
			15
		],
		[
			19,
			8,
			20,
			18,
			16,
			17
		],
		[
			21,
			8,
			15,
			18,
			20,
			19
		]
	],
	[
		[
			9,
			15,
			18,
			19,
			17,
			16
		],
		[
			15,
			9,
			17,
			21,
			19,
			18
		],
		[
			19,
			9,
			18,
			16,
			20,
			17
		]
	],
	[
		[
			10,
			18,
			15,
			21,
			19,
			20
		],
		[
			15,
			10,
			19,
			18,
			16,
			17
		],
		[
			17,
			10,
			19,
			18,
			20,
			21
		]
	],
	[
		[
			11,
			16,
			18,
			19,
			21,
			20
		],
		[
			19,
			11,
			18,
			16,
			21,
			15
		],
		[
			18,
			11,
			16,
			17,
			19,
			21
		]
	],
	[
		[
			14,
			16,
			18,
			20,
			19,
			15
		],
		[
			20,
			14,
			19,
			21,
			18,
			17
		],
		[
			21,
			14,
			20,
			18,
			19,
			15
		]
	]
]


static func visible_items(kind: int, tier: int = -1) -> Array[int]:
	var result: Array[int] = []
	for item_id in range(ITEMS.size()):
		if (ITEMS[item_id].role < 0 or ITEMS[item_id].role == kind) and (tier < 0 or ITEMS[item_id].tier == tier):
			result.append(item_id)
	return result


static func components_owned(inventory: Array, item_id: int) -> Array[int]:
	var available := inventory.duplicate()
	var used: Array[int] = []
	for component in ITEMS[item_id].recipe:
		if component in available:
			used.append(component)
			available.erase(component)
	return used


static func buy_cost(inventory: Array, item_id: int) -> int:
	var cost: int = ITEMS[item_id].cost
	for component in components_owned(inventory, item_id):
		cost -= ITEMS[component].cost
	return cost


static func sell_price(item_id: int) -> int:
	return roundi(ITEMS[item_id].cost * SELL_RATIO)
