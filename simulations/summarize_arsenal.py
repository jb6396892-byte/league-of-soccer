"""Validate the saved 30-game campaign and write its report; never runs matches."""
import json
import re
import statistics
from collections import Counter, defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DATA = ROOT / "work" / "balance-arsenal"
config = json.loads((DATA / "configuration.json").read_text(encoding="utf-8"))
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

held = sum(r["stats"]["possession_seconds"] for rows in role_rows.values() for r in rows)
total_seconds = sum(g["seconds"] for g in games)
blue_wins = sum(g["score"][0] > g["score"][1] for g in games)
overtime_games = sum(g["overtime"] > 0 for g in games)
goals = sum(sum(g["score"]) for g in games)
own_goals = sum(r["stats"]["own_goals"] for rows in role_rows.values() for r in rows)
checks = 0
for name in ("abilities", "economy", "evolution", "new_roles", "tactics", "arsenal"):
    log = (ROOT / "work" / f"equipment-v2-{name}.log").read_text(encoding="utf-8")
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
report = ["# 装备分级、镇域与 E：30 场平衡测试", "", "日期：2026-10-21。全部比赛使用这次完成后的同一套数值，中途未调整游戏参数。", "",
          f"完成 **30 场**、15 组换边对照。蓝队 {blue_wins} 胜、珊瑚队 {30-blue_wins} 胜；总进球 {goals}（乌龙 {own_goals}）。",
          f"{overtime_games} 场进入加时；最长 {max(g['seconds'] for g in games)/60:g} 分钟；累计有效比赛时间 {total_seconds/60:.1f} 分钟。", "",
          "## 测试方法", "",
          "每场 22 名 NPC、60 Hz，运行实际比赛、购买、技能、抢断与进球代码。常规时间 300 秒；平局继续完整 120 秒加时，直到某段结束有胜者。没有测试金币、跳过购买或临时属性加成。",
          "每队固定一名铁闸及每种外场英雄各两名。每组使用相同随机种子，第二场交换双方角色排列、出装路线和首发球权。两边模拟教练都在商店按比分调整阵型；正式人机模式中蓝队由玩家选阵、珊瑚队自动调整。", "",
          "这是一轮固定阵容构成下的自动对抗，位置、整队搭配及装备互相影响。双方拥有相同的英雄数量，因此团队胜率不能解释为单个英雄胜率；也不能直接代表玩家对 NPC 的体感。", "",
          "## 英雄表现", "", "| 英雄 | 出场 | 正常进球 | 抢断 | 控球占比 | 每次出场控球 | W 次数 | E 次数 |", "| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |"]
for kind, name in enumerate(config["hero_names"]):
    rows = role_rows[kind]
    totals = Counter()
    for row in rows:
        totals.update(row["stats"])
    n = len(rows)
    summary["roles"].append({"name": name, "appearances": n, **dict(totals)})
    report.append(f"| {name} | {n} | {totals['goals']} | {totals['tackles']} | {100*totals['possession_seconds']/held:.1f}% | {totals['possession_seconds']/n:.1f}s | {totals['casts']} | {totals['e_casts']} |")
report += ["", "控球占比分母为所有球员持球时间，不含自由球时间；每次出场时长随加时不同。铁闸仅在禁区活动，不与外场角色按进球数直接比较。", "",
           "## E 技能消耗", "", "| 技能 | 单次价格 | 购买次数 | 释放次数 | 终场剩余 | 总支出 |", "| --- | ---: | ---: | ---: | ---: | ---: |"]
for skill, totals in zip(skills, skill_totals):
    report.append(f"| {skill['name']} | {skill['cost']} | {totals['bought']} | {totals['casts']} | {totals['remaining']} | {totals['spent']} |")
report += ["", "默认 NPC 路线选择英雄专属 E、急行或净化；护球可由玩家购买，相关行为检查已执行，但本轮没有 NPC 护球样本。E 释放比例反映这套 AI 的触发条件与战局机会，不能独立证明技能强弱。", "",
           "## 装备购买", "",
           f"660 次球员出场中，{len(first_completions)} 次买到至少一件成装；首件成装的中位购买时间为 {summary['median_first_completed_seconds']:.1f} 秒（仅统计买到者）。六件成装齐备的出场数为 {complete_loadouts}。",
           "小件的购入次数包含后来被合成消耗的材料；现金支出按实际补差价记账，不重复算材料。携带分钟包含重复小件，成装材料被消耗后停止计入。", "",
           "| 装备 | 总价 | 购买次数 | 实际现金支出 | 携带分钟 |", "| --- | ---: | ---: | ---: | ---: |"]
for item, totals in zip(items, item_totals):
    report.append(f"| {item['name']} | {item['cost']} | {totals['purchases']} | {totals['cash']} | {totals['equipped_seconds']/60:.1f} |")
warden, flag = summary["roles"][5], summary["roles"][3]
top = max((r for r in summary["roles"] if r["name"] != "铁闸"), key=lambda r: r["goals"])
report += ["", "## 观察与限制", "",
           f"- 镇域在本样本中完成 {warden['tackles']} 次抢断、{warden['casts']} 次 W、{warden['e_casts']} 次 E；领域累计覆盖敌人 {warden['domain_slow_seconds']:.1f} 人秒。覆盖值按每个领域分别计，重叠部分会重复统计。",
           f"- 旗帜累计有效眩晕命中 {flag['stuns']} 次。场上最高进球角色是{top['name']}，共 {top['goals']} 球；其位置分配与持球机会共同影响结果。",
           f"- {overtime_games}/30 场需要加时。较长的领域持续时间与整体防守可能影响节奏，但没有单独关闭领域的对照组，不能把全部加时归因于镇域。",
           "- 新装备和付费 E 共用个人钱包。短局通常只形成部分成装，而不是必然填满六格；若希望五分钟内普遍六神装，需要另行调整收入或整套价格曲线。",
           "- NPC 不会为了试验而购买每一件商品，也没有人类玩家的精准鼠标目标选择；未购买或样本少的装备、技能需要后续专项对抗，不能用这 30 场宣称全部数值已经平衡。",
           "- 本轮结束后未再修改数值，因此这份报告与当前游戏参数一致。", "",
           "## 实际验证", "",
           f"- {checks} 项相关行为检查通过；Godot 桌面 GPU 预览已验证六角色点击、商店分页、合成补差价、六格装备及出售、E 购买/切换/消耗、领域和帮助界面。",
           f"- 复核全部 {wallets} 个钱包：初始金 + 实际收入 − 装备补差价 − E 支出 = 终场余额；装备材料消耗、六格限制和专属限制一致。",
           "- 每种 E 的购买次数 − 使用次数 = 终场库存；所有比分与进球事件、抢断与失球权、持球与自由球时间、换边角色/出装和全队升级账目一致。", "",
           "## 场次", "", "| 场次 | 蓝:珊瑚 | 有效秒数 | 加时段数 |", "| --- | --- | ---: | ---: |"]
for game in games:
    report.append(f"| {game['round']:02} | {game['score'][0]}:{game['score'][1]} | {game['seconds']:g} | {game['overtime']} |")
report += ["", "原始逐场数据、每次交易和 E 释放记录位于 `work/balance-arsenal/match-01.json` 至 `match-30.json`；配置存于 `configuration.json`，汇总存于 `summary.json`。",
           "运行 `python -X utf8 simulations/summarize_arsenal.py` 只复核并生成报告，不会启动额外比赛。"]
(DATA / "summary.json").write_text(json.dumps(summary, ensure_ascii=False, indent=2), encoding="utf-8")
(ROOT / "BALANCE_ARSENAL_30.md").write_text("\n".join(report) + "\n", encoding="utf-8")
print(json.dumps({k: v for k, v in summary.items() if k not in ("roles", "items", "skills")}, ensure_ascii=False))
print("Saved BALANCE_ARSENAL_30.md; all 30 games and 660 wallets reconciled")
