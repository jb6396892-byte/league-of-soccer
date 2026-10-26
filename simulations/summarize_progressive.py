"""Validate the saved 30-game campaign and write its report; never runs matches."""
import json
import re
import statistics
from collections import Counter, defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DATA = ROOT / "work" / "balance-progressive"
config = json.loads((DATA / "configuration-01.json").read_text(encoding="utf-8"))
games = [json.loads(p.read_text(encoding="utf-8")) for p in sorted(DATA.glob("match-*.json"))]
assert [g["round"] for g in games] == list(range(1, 31)), "Need exactly 30 completed rounds"
items, skills = config["items"], config["skills"]
role_rows = defaultdict(list)
item_totals = [Counter() for _ in items]
skill_totals = [Counter() for _ in skills]
first_completions = []
wallets = 0
complete_loadouts = 0

for game in games:
    config = json.loads((DATA / f"configuration-{game['configuration']:02}.json").read_text(encoding="utf-8"))
    items, skills = config["items"], config["skills"]
    rows = game["players"]
    assert len(rows) == 22 and game["score"][0] != game["score"][1]
    assert game["seconds"] == 300 + 120 * game["overtime"]
    assert Counter(row["role"] for row in rows) == Counter({0: 4, 1: 4, 2: 4, 3: 4, 4: 2, 5: 4})
    assert sum(p["stats"]["tackles"] for p in rows) == sum(p["stats"]["turnovers"] for p in rows)
    assert abs(sum(p["stats"]["possession_seconds"] for p in rows) + game["loose_seconds"] - game["seconds"]) < 0.02
    assert sum(game["score"]) == len(game["goals"]) == sum(p["stats"]["goals"] + p["stats"]["own_goals"] for p in rows)
    assert [sum(event["team"] == side for event in game["goals"]) for side in (0, 1)] == game["score"]
    for event in game["goals"]:
        assert 0 <= event["time"] <= game["seconds"]
    for item_id, usage in enumerate(game["equipment"]):
        item_totals[item_id].update({k: v for k, v in usage.items() if k != "name"})
    for row in rows:
        team, shirt = row["team"], row["shirt_number"]
        same_player = lambda event: event["team"] == team and event["shirt_number"] == shirt
        purchases = [p for p in game["purchases"] if same_player(p)]
        e_purchases = [p for p in game["e_purchases"] if same_player(p)]
        e_casts = [p for p in game["e_casts"] if same_player(p)]
        inv, team_buys = [], [0, 0]
        for purchase in purchases:
            item_id = purchase["item"]
            item = items[item_id]
            assert item["role"] in (-1, row["role"])
            available = inv.copy()
            consumed = []
            for component in item["recipe"]:
                if component in available:
                    consumed.append(component)
                    available.remove(component)
            assert purchase["components"] == consumed
            assert purchase["cost"] == item["cost"] - sum(items[c]["cost"] for c in consumed)
            if "team_upgrade" in item:
                assert len(inv) == 6 and all(items[i]["tier"] == 1 for i in inv)
                team_buys[item["team_upgrade"]] += 1
            else:
                if item["tier"] == 1:
                    assert item_id not in inv
                for component in consumed:
                    inv.remove(component)
                inv.append(item_id)
                assert len(inv) <= 6
            item_totals[item_id]["purchases"] += 1
            item_totals[item_id]["cash"] += purchase["cost"]
        assert inv == row["inventory"] and team_buys == row["team_purchases"]
        assert row["gold"] == 500 + row["stats"]["gold_earned"] - sum(p["cost"] for p in purchases + e_purchases)
        assert row["gold"] >= 0
        bought, used = Counter(), Counter()
        for purchase in e_purchases:
            skill_id = purchase["skill"]
            assert skills[skill_id]["role"] in (-1, row["role"])
            assert purchase["cost"] == skills[skill_id]["cost"]
            bought[skill_id] += 1
            skill_totals[skill_id]["bought"] += 1
            skill_totals[skill_id]["spent"] += purchase["cost"]
        for cast in e_casts:
            used[cast["skill"]] += 1
            skill_totals[cast["skill"]]["casts"] += 1
        assert len(e_casts) == row["stats"]["e_casts"]
        for skill_id in set(bought) | set(used):
            assert bought[skill_id] - used[skill_id] == row["e_charges"].get(str(skill_id), 0) >= 0
            skill_totals[skill_id]["remaining"] += bought[skill_id] - used[skill_id]
        completed = [p for p in purchases if items[p["item"]]["tier"] == 1]
        if completed:
            first_completions.append(completed[0]["time"])
        complete_loadouts += len(inv) == 6 and all(items[i]["tier"] == 1 for i in inv)
        role_rows[row["role"]].append({**row, "seconds": game["seconds"]})
        wallets += 1
    assert [[sum(p["team_purchases"][i] for p in rows if p["team"] == t) for i in (0, 1)] for t in (0, 1)] == game["team_upgrades"]

for first, second in zip(games[::2], games[1::2]):
    assert first["pair"] == second["pair"] and first["seed"] == second["seed"]
    assert first["kickoff"] == 0 and second["kickoff"] == 1
    for i, actor in enumerate(first["starting"]):
        mirrored = second["starting"][(i + 11) % 22]
        assert (actor["role"], actor["build"]) == (mirrored["role"], mirrored["build"])

def read_catalog(filename):
    return [json.loads(line.strip().rstrip(',')) for line in (ROOT / "scripts" / filename).read_text(encoding="utf-8").splitlines() if line.lstrip().startswith('{"name":')]

items = read_catalog("equipment.gd")
skills = read_catalog("purchasable_skills.gd")
adjustments = json.loads((DATA / "adjustments.json").read_text(encoding="utf-8"))
assert [a["after"] for a in adjustments] == list(range(2,31,2))
assert all(totals["purchases"] > 0 for totals in item_totals), "Every catalog item must see actual purchases"
def constants(filename, names):
    source = (ROOT / "scripts" / filename).read_text(encoding="utf-8")
    return {name: json.loads(re.search(rf"(?m)^const {name} := (.+)$", source)[1]) for name in names}

final_catalog = {"items": items, "skills": skills,
                 "roles": constants("archetypes.gd", ["SPEED", "HIT_SCALE", "COOLDOWN", "DURATION", "SPRINT_MULTIPLIER", "DOMAIN_RADIUS", "DOMAIN_RANGE", "THROW_SPEED", "THROW_RANGE", "HIT_WIDTH_GROWTH", "HIT_SPEED_GROWTH"]),
                 "economy": constants("equipment.gd", ["START_GOLD", "STIPEND_GOLD", "STIPEND_SECONDS", "SUPPLY_SECONDS", "TEAM_SPEED_GAIN", "TEAM_SPEED_LOSS"]),
                 "note": "After the fifteenth adjustment; no 31st full match"}
(DATA / "configuration-final.json").write_text(json.dumps(final_catalog,ensure_ascii=False,indent=2),encoding="utf-8")

held = sum(r["stats"]["possession_seconds"] for rows in role_rows.values() for r in rows)
total_seconds = sum(g["seconds"] for g in games)
blue_wins = sum(g["score"][0] > g["score"][1] for g in games)
overtime_games = sum(g["overtime"] > 0 for g in games)
goals = sum(sum(g["score"]) for g in games)
own_goals = sum(r["stats"]["own_goals"] for rows in role_rows.values() for r in rows)
checks = 0
for name in ("settings", "abilities", "economy", "evolution", "new_roles", "tactics", "arsenal"):
    log = (ROOT / "work" / f"progressive-{name}.log").read_text(encoding="utf-8")
    result = re.search(r"RESULT: (\d+) checks, (\d+) failures", log)
    assert result and result[2] == "0", name
    checks += int(result[1])

summary = {
    "games": 30, "wallets_validated": wallets, "checks_passed": checks,
    "blue_wins": blue_wins, "coral_wins": 30 - blue_wins,
    "goals": goals, "own_goals": own_goals, "overtime_games": overtime_games,
    "seconds": total_seconds, "first_completed_buyers": len(first_completions),
    "median_first_completed_seconds": statistics.median(first_completions) if first_completions else None,
    "complete_loadouts": complete_loadouts, "roles": [],
    "items": [dict(row) for row in item_totals], "skills": [dict(row) for row in skill_totals],
}
report = ["# 30 场逐组平衡调整与赛前设置", "", "日期：2026-10-22。按用户确认，全部使用一般难度、5 分钟常规时间；每两场结束后调整一次，共 15 轮。", "",
          f"完成 **30 场**、15 组换边对照。蓝队 {blue_wins} 胜、珊瑚队 {30-blue_wins} 胜；总进球 {goals}（乌龙 {own_goals}）。",
          f"{overtime_games} 场进入加时；最长 {max(g['seconds'] for g in games)/60:g} 分钟；累计有效比赛时间 {total_seconds/60:.1f} 分钟。", "",
          "## 测试方法", "",
          "每场 22 名 NPC、60 Hz，运行实际比赛、购买、技能、抢断与进球代码。常规时间 300 秒；平局继续完整 120 秒加时，直到某段结束有胜者。没有测试金币、跳过购买或临时属性加成。",
          "每队固定一名铁闸及每种外场英雄各两名。每组使用相同随机种子，第二场交换双方角色排列、出装路线和首发球权。两边模拟教练都在商店按比分调整阵型；正式人机模式中蓝队由玩家选阵、珊瑚队自动调整。", "",
          "本报告汇总 15 套先后使用的配置，不是最终参数的 30 场验证。第 30 场后的第 15 次修改另做行为和图形检查，没有运行第 31 场。位置、整队搭配及装备互相影响。双方拥有相同的英雄数量，因此团队胜率不能解释为单个英雄胜率；也不能直接代表玩家对 NPC 的体感。", "",
          "## 英雄表现", "", "| 英雄 | 出场 | 首发前锋 | 正常进球 | 抢断 | 控球占比 | 每次出场控球 | W 次数 | E 次数 |", "| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |"]
for kind, name in enumerate(config["hero_names"]):
    rows = role_rows[kind]
    totals = Counter()
    for row in rows:
        totals.update(row["stats"])
    n = len(rows)
    forwards = sum(p["role"] == kind and p["line"] == 3 for g in games for p in g["starting"])
    summary["roles"].append({"name": name, "appearances": n, **dict(totals)})
    report.append(f"| {name} | {n} | {forwards} | {totals['goals']} | {totals['tackles']} | {100*totals['possession_seconds']/held:.1f}% | {totals['possession_seconds']/n:.1f}s | {totals['casts']} | {totals['e_casts']} |")
report += ["", "首发前锋只计开场阵型，比赛内仍会换阵。控球占比分母为所有球员持球时间，不含自由球时间；每次出场时长随加时不同。铁闸仅在禁区活动，不与外场角色按进球数直接比较。", "",
           "## E 技能消耗", "", "| 技能 | 单次价格 | 购买次数 | 释放次数 | 终场剩余 | 总支出 |", "| --- | ---: | ---: | ---: | ---: | ---: |"]
for skill, totals in zip(skills, skill_totals):
    report.append(f"| {skill['name']} | {skill['cost']} | {totals['bought']} | {totals['casts']} | {totals['remaining']} | {totals['spent']} |")
report += ["", "第 2 场后加入护球 NPC 路线。表中单价为最终价格，累计支出按每场当时的实际价格结算；E 释放比例受触发条件和比赛机会影响。", "",
           "## 装备购买", "",
           f"660 次球员出场中，{len(first_completions)} 次买到至少一件成装；首件成装的中位购买时间为 {summary['median_first_completed_seconds']:.1f} 秒（仅统计买到者）。六件成装齐备的出场数为 {complete_loadouts}。",
           "全部 22 种装备均有实际 NPC 购买。表中价格是最后一次调整后的价格；累计现金按各场当时价格和材料补差价计算。携带分钟包含重复小件，材料消耗后停止计入。", "",
           "| 装备 | 总价 | 购买次数 | 实际现金支出 | 携带分钟 |", "| --- | ---: | ---: | ---: | ---: |"]
for item, totals in zip(items, item_totals):
    report.append(f"| {item['name']} | {item['cost']} | {totals['purchases']} | {totals['cash']} | {totals['equipped_seconds']/60:.1f} |")
warden, flag = summary["roles"][5], summary["roles"][3]
top = max((r for r in summary["roles"] if r["name"] != "铁闸"), key=lambda r: r["goals"])
report += ["", "## 观察与限制", "",
           f"- 镇域在本样本中完成 {warden['tackles']} 次抢断、{warden['casts']} 次 W、{warden['e_casts']} 次 E；领域累计覆盖敌人 {warden['domain_slow_seconds']:.1f} 人秒。覆盖值按每个领域分别计，重叠部分会重复统计。",
           f"- 旗帜累计有效眩晕命中 {flag['stuns']} 次。场上最高进球角色是{top['name']}，共 {top['goals']} 球；其位置分配与持球机会共同影响结果。",
           f"- {overtime_games}/30 场需要加时。较长的领域持续时间与整体防守可能影响节奏，但没有单独关闭领域的对照组，不能把全部加时归因于镇域。",
           "- 成装节奏须结合逐组记录判断：前两场为原经济基线，此后逐步调整收入、价格、被动及路线，不能只用全部场次的中位数代表最终节奏。",
           "- 装备覆盖来自正式游戏的价格、收入与 NPC 路线，不向测试赠送装备或金币；购买次数也受到路线安排影响，不是独立的装备胜率。全部商品有人购买不等于选择率均衡。",
           "- 第 30 场后仍按要求执行了第 15 轮调整。最终价格见上表，最终改动已通过交易、技能检查与图形预览；本汇总混合先前 15 套参数。", "",
           "## 实际验证", "",
           f"- {checks} 项相关行为检查通过；Godot 桌面 GPU 预览已验证时长与难度点击、启动计时、最终商店与技能显示。5/15 分钟和简单/一般/困难另有针对性行为检查，未混入这 30 场。",
           f"- 复核全部 {wallets} 个钱包：初始金 + 实际收入 − 装备补差价 − E 支出 = 终场余额；装备材料消耗、六格限制和专属限制一致。",
           "- 每种 E 的购买次数 − 使用次数 = 终场库存；所有比分与进球事件、抢断与失球权、持球与自由球时间、换边角色/出装和全队升级账目一致。", "",
           "## 场次", "", "| 场次 | 蓝:珊瑚 | 有效秒数 | 加时段数 |", "| --- | --- | ---: | ---: |"]
for game in games:
    report.append(f"| {game['round']:02} | {game['score'][0]}:{game['score'][1]} | {game['seconds']:g} | {game['overtime']} |")
report += ["", "原始逐场数据、每次交易和 E 释放记录位于 `work/balance-progressive/match-01.json` 至 `match-30.json`；逐组配置存于 `configuration-01.json` 至 `configuration-15.json`，最终目录存于 `configuration-final.json`，汇总存于 `summary.json`。",
           "运行 `python -X utf8 simulations/summarize_progressive.py` 只复核并生成报告，不会启动额外比赛。"]
report += ["", "## 各组购买节奏与领域覆盖", "", "第 9 场起，每 90 秒有效比赛时间开放 15 秒补给，原地续赛；镇域领域同步从 40 秒 / 12 米改为 12 秒 / 10 米。覆盖人秒含重叠且未按减速抗性折算，仅用于观察控场规模，不能独立衡量英雄强度。", "",
           "| 场次 | 首件成装中位秒数 | 六成装出场 / 44 | 镇域覆盖人秒 / 比赛分钟 |", "| --- | ---: | ---: | ---: |"]
for first, second in zip(games[::2], games[1::2]):
    pair_games = [first, second]
    pair_config = json.loads((DATA / f"configuration-{first['configuration']:02}.json").read_text(encoding="utf-8"))
    pair_items = pair_config["items"]
    first_times = []
    full = 0
    cover = 0
    for g in pair_games:
        for row in g["players"]:
            purchases = [p for p in g["purchases"] if p["team"] == row["team"] and p["shirt_number"] == row["shirt_number"] and pair_items[p["item"]]["tier"] == 1]
            if purchases:
                first_times.append(purchases[0]["time"])
            full += len(row["inventory"]) == 6 and all(pair_items[i]["tier"] == 1 for i in row["inventory"])
            cover += row["stats"]["domain_slow_seconds"]
    report.append(f"| {first['round']}–{second['round']} | {statistics.median(first_times):.1f} | {full} | {cover * 60 / (first['seconds']+second['seconds']):.1f} |")
report += ["", "## 每两场后的调整", "", "下列 15 次均在对应两场完成后依据数据执行，原始前后值存于 adjustments.json。"]
for change in adjustments:
    report += ["", f"### 第 {change['after']-1}–{change['after']} 场后", "", change["reason"], ""]
    for edit in change["changes"]:
        if "implementation" in edit:
            report.append("- " + edit["implementation"])
        elif "constant" in edit:
            if edit["constant"] == "NPC_BUILDS":
                report.append("- 调整英雄出装路线，具体顺序见本轮配置与 adjustments.json。")
            else:
                report.append(f"- {edit['constant']}：{edit['old']} → {edit['new']}")
        elif edit["field"] not in ("lines", "tag"):
            name = items[edit["item"]]["name"] if edit["file"] == "equipment.gd" else skills[edit["item"]]["name"]
            report.append(f"- {name} / {edit['field']}：{edit['old']} → {edit['new']}")
summary["adjustments"] = adjustments
summary["equipment_coverage"] = len(items)
(DATA / "summary.json").write_text(json.dumps(summary, ensure_ascii=False, indent=2), encoding="utf-8")
(ROOT / "BALANCE_PROGRESSIVE_30.md").write_text("\n".join(report) + "\n", encoding="utf-8")
print(json.dumps({k: v for k, v in summary.items() if k not in ("roles", "items", "skills", "adjustments")}, ensure_ascii=False))
print("Saved BALANCE_PROGRESSIVE_30.md; all 30 games and 660 wallets reconciled")
