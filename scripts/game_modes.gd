extends RefCounted
## Fixed objectives for the conquest route; free matches retain their own settings.
const CHALLENGES := [
	{"id": "first_goal", "title": "开门见喜", "seconds": 90, "difficulty": 0, "team_size": 11, "score": [0, 0], "goal": "goals", "target": 1, "role": -1, "kickoff": 0, "seed": 8800, "brief": ["90 秒内本队攻入 1 球", "达标立即过关，允许失球", "先熟悉接应，再寻找射门空间"]},
	{"id": "protect_lead", "title": "守住优势", "seconds": 90, "difficulty": 0, "team_size": 11, "score": [1, 0], "goal": "result", "target": 1, "role": -1, "kickoff": 1, "seed": 8801, "brief": ["从 1:0 领先开始", "守住 90 秒，终场仍领先", "对手开球，练习回防与控球"]},
	{"id": "first_win", "title": "首战告捷", "seconds": 90, "difficulty": 0, "team_size": 11, "score": [0, 0], "goal": "result", "target": 1, "role": -1, "kickoff": 0, "seed": 8803, "brief": ["90 秒结束时比分领先", "从 0:0 开始，平局判负", "兼顾进攻与身后的防线"]},
	{"id": "double_strike", "title": "双响练习", "seconds": 90, "difficulty": 0, "team_size": 11, "score": [0, 0], "goal": "goals", "target": 2, "role": -1, "kickoff": 0, "seed": 8802, "brief": ["90 秒内本队攻入 2 球", "达标立即过关，允许失球", "连续组织两次有效进攻"]},
	{"id": "two_goal_margin", "title": "两球领先", "seconds": 75, "difficulty": 0, "team_size": 11, "score": [0, 0], "goal": "result", "target": 2, "role": -1, "kickoff": 0, "seed": 8804, "brief": ["终场至少净胜 2 球", "75 秒，领先后仍需守住", "为进入一般难度做好准备"]},
	{"id": "equalizer", "title": "绝境扳平", "seconds": 150, "difficulty": 1, "team_size": 11, "score": [0, 2], "goal": "result", "target": 0, "role": -1, "kickoff": 0, "seed": 8805, "brief": ["从 0:2 落后开始", "150 秒结束时至少扳平", "允许平局，追分赏金照常"]},
	{"id": "last_line", "title": "最后一道防线", "seconds": 90, "difficulty": 1, "team_size": 11, "score": [0, 0], "goal": "clean_sheet", "target": 0, "role": 4, "kickoff": 1, "seed": 8702, "brief": ["操控铁闸，90 秒不失球", "对手先开球，接住后快出球", "丢球立即失败，零封即过关"]},
	{"id": "lightning", "title": "闪电开局", "seconds": 90, "difficulty": 1, "team_size": 11, "score": [0, 0], "goal": "result", "target": 1, "role": -1, "kickoff": 0, "seed": 8700, "brief": ["90 秒结束时比分领先", "时间更紧，抓住第一次机会", "平局判负，不进入加时"]},
	{"id": "ten_player_escape", "title": "十人突围", "seconds": 90, "difficulty": 1, "team_size": 10, "score": [0, 0], "goal": "result", "target": 1, "role": -1, "kickoff": 0, "seed": 8806, "brief": ["10 人迎战 11 人一般 AI", "90 秒结束时比分领先", "少一名中场，练习协防补位"]},
	{"id": "comeback", "title": "逆风翻盘", "seconds": 150, "difficulty": 1, "team_size": 11, "score": [0, 1], "goal": "result", "target": 1, "role": -1, "kickoff": 0, "seed": 8701, "brief": ["从 0:1 落后开始", "150 秒结束时反超对手", "必须取胜，扳平仍不够"]},
	{"id": "hold_the_line", "title": "强敌试锋", "seconds": 240, "difficulty": 2, "team_size": 11, "score": [0, 0], "goal": "goals", "target": 1, "role": -1, "kickoff": 0, "seed": 8703, "brief": ["240 秒内攻入困难 AI 1 球", "达标立即过关，允许失球", "先找到空当，再迎接多球考验"]},
	{"id": "storm", "title": "进攻风暴", "seconds": 240, "difficulty": 2, "team_size": 11, "score": [0, 0], "goal": "goals", "target": 3, "role": -1, "kickoff": 0, "seed": 8703, "brief": ["240 秒内本队攻入 3 球", "达标立即过关，允许失球", "不要求比分领先"]},
	{"id": "elite_comeback", "title": "强敌逆转", "seconds": 240, "difficulty": 2, "team_size": 11, "score": [0, 1], "goal": "result", "target": 1, "role": -1, "kickoff": 0, "seed": 8808, "brief": ["落后 0:1 迎战困难 AI", "240 秒结束时完成反超", "善用补给，兼顾进攻与防守"]},
	{"id": "short_handed", "title": "少一人的决胜", "seconds": 300, "difficulty": 2, "team_size": 10, "score": [0, 0], "goal": "result", "target": 1, "role": -1, "kickoff": 0, "seed": 8704, "brief": ["10 人迎战 11 人困难 AI", "300 秒结束时比分领先", "少一名中场，平局判负"]},
	{"id": "nine_player_miracle", "title": "九人奇迹", "seconds": 360, "difficulty": 2, "team_size": 9, "score": [0, 1], "goal": "result", "target": 1, "role": -1, "kickoff": 0, "seed": 8809, "brief": ["9 对 11，且开局落后 0:1", "360 秒内逆转困难 AI", "终场必须领先，最终考验"]}
]
const CHAPTERS := ["初登赛场", "逆境磨炼", "巅峰征服"]
const LEGACY_IDS := ["lightning", "comeback", "last_line", "storm", "short_handed"]


static func outcome(index: int, score: Array, expired: bool) -> int:
	# -1: keep playing; 0: failed; 1: cleared.
	var rules: Dictionary = CHALLENGES[index]
	match rules.goal:
		"clean_sheet":
			if score[1] > 0:
				return 0
			return 1 if expired else -1
		"goals":
			if score[0] >= rules.target:
				return 1
			return 0 if expired else -1
	return int(score[0] - score[1] >= rules.target) if expired else -1


static func progress_text(index: int, score: Array) -> String:
	var rules: Dictionary = CHALLENGES[index]
	if rules.goal == "goals":
		return "本队进球 %d / %d" % [score[0], rules.target]
	if rules.goal == "clean_sheet":
		return "失球 %d · 必须保持零封" % score[1]
	return "当前净胜球 %+d · 终场至少 %+d" % [score[0] - score[1], rules.target]
