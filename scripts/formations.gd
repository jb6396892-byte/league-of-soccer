extends RefCounted
## Tactical duties are independent from hero types and shirt numbers.

enum Line { KEEPER, BACK, MID, FRONT }
const LINE_NAMES := ["门将", "后卫", "中场", "前锋"]
const NAMES := ["4-4-2", "4-3-3", "3-4-3", "3-5-2", "5-4-1"]
const STYLES := ["均衡", "边路进攻", "压上追分", "中场控制", "稳守反击"]
const COUNTS := [[4, 4, 2], [4, 3, 3], [3, 4, 3], [3, 5, 2], [5, 4, 1]]
const DEPTHS := [[-32.0, -18.0, -6.0], [-32.0, -18.0, -5.0], [-29.0, -16.0, -5.0], [-31.0, -17.0, -6.0], [-35.0, -21.0, -6.0]]
const PREFERRED_LINE := [Line.FRONT, Line.MID, Line.FRONT, Line.BACK, Line.KEEPER, Line.BACK]
const HERO_WEIGHTS := [[0.05, 0.15, 0.05, 0.375, 0.0, 0.375], [0.075, 0.70, 0.075, 0.075, 0.0, 0.075], [0.40, 0.12, 0.40, 0.04, 0.0, 0.04]]


static func slots(index: int) -> Array:
	var result := [{"home": Vector3(-44.5, 0, 0), "line": Line.KEEPER}]
	for row in range(3):
		var count: int = COUNTS[index][row]
		var width := 17.0 if row == 2 else 22.0
		if count == 2:
			width = 9.0
		for i in range(count):
			var z := 0.0 if count == 1 else lerpf(-width, width, float(i) / (count - 1))
			result.append({"home": Vector3(DEPTHS[index][row], 0, z), "line": row + 1})
	return result


static func random_hero(line: int, rng: RandomNumberGenerator) -> int:
	return rng.rand_weighted(PackedFloat32Array(HERO_WEIGHTS[line - 1]))


static func opponent_formation(goal_difference: int, rng: RandomNumberGenerator) -> int:
	if goal_difference >= 2:
		return 4
	if goal_difference == 1:
		return 0 if rng.randf() < 0.5 else 4
	if goal_difference <= -2:
		return 2
	if goal_difference == -1:
		return 1 if rng.randf() < 0.5 else 3
	return [0, 1, 3][rng.randi_range(0, 2)]
