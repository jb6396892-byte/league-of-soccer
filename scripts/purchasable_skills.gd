extends RefCounted
## Purchased charges persist across kickoffs; one selected E per hero.

enum Kind { HASTE, CLEANSE, CONTROL, RUNNER, GUARD, CHARGER, STRIKER, KEEPER, WARDEN }
const NPC_SKILLS := [[3, 0, 2], [4, 0, 1], [5, 2, 1], [6, 0, 1], [7, 0, 1], [8, 0, 1]]
const SKILLS := [
	{"name": "急行", "role": -1, "cost": 90, "cooldown": 12.0, "lines": ["自身移速 +20%，持续 3 秒", "追球与回防 · 按 E 即用"]},
	{"name": "净化", "role": -1, "cost": 90, "cooldown": 18.0, "lines": ["解除眩晕并免疫控制 2 秒", "眩晕时也能释放"]},
	{"name": "护球", "role": -1, "cost": 90, "cooldown": 16.0, "lines": ["持球时获得 1.3 秒球权保护", "无球时不消耗次数"]},
	{"name": "追风", "role": 0, "cost": 120, "cooldown": 18.0, "lines": ["自身移速 +25%，持续 3 秒", "与 W 加速取较强值"]},
	{"name": "震荡", "role": 1, "cost": 130, "cooldown": 20.0, "lines": ["脚下 6 米领域减速敌人 40%", "固定领域持续 4 秒"]},
	{"name": "折跃", "role": 2, "cost": 150, "cooldown": 18.0, "lines": ["向鼠标瞬移，最远 5 米", "可带球 · 受球场边界限制"]},
	{"name": "鼓舞", "role": 3, "cost": 120, "cooldown": 20.0, "lines": ["8 米内友军移速 +18%，4 秒", "包含自身 · 加速取最强值"]},
	{"name": "封锁", "role": 4, "cost": 110, "cooldown": 20.0, "lines": ["开启 2 秒扑救窗口", "同时免疫控制 2 秒"]},
	{"name": "坚守", "role": 5, "cost": 130, "cooldown": 22.0, "lines": ["8 米内友军解除并免疫控制", "持续 2.5 秒 · 包含自身"]}
]


static func visible_skills(kind: int) -> Array[int]:
	var result: Array[int] = [kind + 3]
	result.append_array([Kind.HASTE, Kind.CLEANSE, Kind.CONTROL])
	return result
