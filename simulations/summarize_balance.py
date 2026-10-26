"""Summarize campaign two and compare its saved data with campaign one."""
import json
import math
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
WORK = ROOT / "work" / "balance-v2"
previous = json.loads((ROOT / "work/balance-ten.json").read_text(encoding="utf-8-sig"))
blocks = [json.loads((WORK / f"balance-batch-{n:02}.json").read_text(encoding="utf-8-sig")) for n in range(1, 6)]
adjustments = json.loads((WORK / "balance-adjustments.json").read_text(encoding="utf-8-sig"))
games = [game for block in blocks for game in block["games"]]
assert [g["round"] for g in games] == list(range(1, 11))
assert [a["after_round"] for a in adjustments] == [2, 4, 6, 8, 10]
for game in games:
    rows = game["players"]
    assert len(rows) == 22
    assert sum(p["stats"]["goals"] + p["stats"]["own_goals"] for p in rows) == sum(game["score"])
    assert sum(p["stats"]["tackles"] for p in rows) == sum(p["stats"]["turnovers"] for p in rows)
    assert math.isclose(sum(p["stats"]["possession_seconds"] for p in rows) + game["loose_ball_seconds"], 300, abs_tol=1e-6)
for block in blocks:
    first, second = [g["players"] for g in block["games"]]
    assert [p["role"] for p in first] == [p["role"] for p in second[11:] + second[:11]]
    assert block["parameters"]["cooldown"][2] == 4
    assert math.isclose(block["parameters"]["slow_multiplier"], 0.7)
for old_game, game in zip(previous["games"], games):
    assert old_game["seed"] == game["seed"]
    assert [p["role"] for p in old_game["players"]] == [p["role"] for p in game["players"]]

names = ["疾风", "磁卫", "跃影"]
metrics = list(games[0]["players"][0]["stats"])
all_rows = [p for g in games for p in g["players"]]
held = sum(p["stats"]["possession_seconds"] for p in all_rows)
loose = sum(g["loose_ball_seconds"] for g in games)
totals = []
for kind, name in enumerate(names):
    rows = [p for p in all_rows if p["role"] == kind]
    outfield = [p for p in rows if not p["goalkeeper"]]
    total = {"name": name, "appearances": len(rows), "outfield_appearances": len(outfield),
             "forward_appearances": sum(p["shirt_number"] >= 10 for p in rows)}
    total.update({metric: sum(p["stats"][metric] for p in rows) for metric in metrics})
    total["possession_percent"] = total["possession_seconds"] / held * 100
    total["outfield"] = {metric: sum(p["stats"][metric] for p in outfield) for metric in metrics}
    totals.append(total)

source = (ROOT / "scripts/archetypes.gd").read_text(encoding="utf-8-sig")
def constant(name):
    return json.loads(re.search(rf"^const {re.escape(name)} := (.+)$", source, re.M)[1])
final_parameters = {name: constant(name) for name in ["SPEED", "HIT_SCALE", "DURATION", "COOLDOWN", "SPRINT_MULTIPLIER", "SLOW_RADIUS", "SLOW_MULTIPLIER", "CHARGE_DURATION", "AI_CHARGE_MIN_FRACTION", "DASH_MIN_DISTANCE", "DASH_MAX_DISTANCE", "DASH_SPEED"]}
verification = re.search(r"RESULT: (\d+) checks, (\d+) failures", (WORK / "abilities-final.log").read_text(encoding="utf-8"))
assert verification is not None and int(verification[2]) == 0
result = {"games": games, "blocks": [{k: b[k] for k in ["batch", "parameters", "totals"]} for b in blocks],
          "totals": totals, "adjustments": adjustments, "final_parameters": final_parameters,
          "held_seconds": held, "loose_ball_seconds": loose,
          "previous_totals": previous["totals"], "same_rosters_and_seeds": True,
          "checks_passed": int(verification[1]),
          "final_adjustment_full_match_validated": False}
(WORK / "balance-ten.json").write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding="utf-8")

lines = ["# 第二轮 10 场模拟对抗与大胆调参", "", "2026-10-20。先按要求将跃影（月影）的 W 冷却改为 4 秒、磁卫（刺猬）的 W 减速改为 30%，再完成新的 10 场，每 2 场调整一组，共 5 组。两项指定数值在本轮全程保持。每场 5 分钟、60 Hz，22 名球员由实际游戏 NPC 逻辑控制。", "",
"## 数据口径", "",
"- 抢断：直接从敌方持球队员脚下夺得控制权；同时给对方记一次被抢断。接住自由球不计抢断。",
"- 拦截：成功接住自由球，且上一触球者属于对方；被高速球撞到但未接住不计拦截。",
"- 控球率：该角色实际持球秒数 ÷ 所有角色持球秒数。飞行、自由滚动时记为无人控球；进球等待与暂停不计比赛时间。",
"- 进球：过线前最后触球角色；乌龙球另列。踢球次数包含传球与射门。",
"- 每组随机分配接近相等的非门将角色人数（7/7/6），第二场交换两队对应位置的角色阵容与开球方。5 组使用不同阵容；种子为 9100–9109。",
"- 调整同时参考非门将每人次数据，减少角色人数与门将影响。前锋位置仍会影响进球，因此这不是单角色胜率或严格因果实验。", "",
"## 10 场累计", "",
"这些总数覆盖逐步调整中的多个版本，不代表最终参数单独跑 10 场的结果。", "",
"| 角色 | 出场人次 | 其中前锋 | 进球 | 乌龙球 | 抢断 | 拦截 | 控球秒数 | 控球率 |", "| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |"]
for t in totals:
    lines.append(f"| {t['name']} | {t['appearances']} | {t['forward_appearances']} | {t['goals']} | {t['own_goals']} | {t['tackles']} | {t['interceptions']} | {t['possession_seconds']:.1f} | {t['possession_percent']:.1f}% |")
lines += ["", f"有效比赛时间合计 3000 秒；持球 {held:.1f} 秒，无人控球 {loose:.1f} 秒（{loose / 30:.1f}%）。乌龙球 {sum(t['own_goals'] for t in totals)} 个。抢断合计 {sum(t['tackles'] for t in totals)} 次，与被抢断次数一致。", "",
"| 角色 | 非门将人次 | 每人次进球 | 每人次抢断 | 每人次持球秒数 | 被抢断 | 踢球次数 | W 次数 |", "| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |"]
for t in totals:
    n = t["outfield_appearances"]
    o = t["outfield"]
    lines.append(f"| {t['name']} | {n} | {o['goals']/n:.3f} | {o['tackles']/n:.2f} | {o['possession_seconds']/n:.2f} | {t['turnovers']} | {t['kicks']} | {t['casts']} |")
lines += ["", "最后三列为所有位置合计；前三个每人次指标只使用非门将。", "", "## 与上一轮对比", "",
"两轮阵容、位置、出场次数与随机种子一致，原始文件已核对。但两轮各自包含多次调参，因此以下是整个迭代过程的对比，不是最终配置之间的单变量实验。", "",
"| 角色 | 进球：上轮 → 本轮 | 抢断：上轮 → 本轮 | 控球率：上轮 → 本轮 |", "| --- | --- | --- | --- |"]
for old, new in zip(previous["totals"], totals):
    lines.append(f"| {new['name']} | {old['goals']} → {new['goals']} | {old['tackles']} → {new['tackles']} | {old['possession_percent']:.1f}% → {new['possession_percent']:.1f}% |")
lines += ["", "上轮无乌龙球，本轮跃影有 4 个乌龙球（第 3 场 1 个、第 4 场 3 个），不混入正常进球统计。", "",
"## 逐场比分与角色数据", "", "下表三项数值均按 **疾风 / 磁卫 / 跃影** 排列；比分包含乌龙球，角色进球列不含。", "", "| 场次 | 蓝队 : 珊瑚队 | 进球 | 抢断 | 控球率 |", "| --- | --- | --- | --- | --- |"]
for g in games:
    roles = g["roles"]
    goals = " / ".join(str(int(r["goals"])) for r in roles)
    tackles = " / ".join(str(int(r["tackles"])) for r in roles)
    possession = " / ".join(f"{r['possession_percent']:.1f}%" for r in roles)
    lines.append(f"| {g['round']} | {g['score'][0]} : {g['score'][1]} | {goals} | {tackles} | {possession} |")
lines += ["", "## 每两场调整记录", "", "调整可以同时改变多个相关数值；后一组使用前一组调整后的参数。", "", "| 调整时点 | 角色 | 参数 | 修改前 → 修改后 |", "| --- | --- | --- | --- |"]
labels = {"CHARGE_DURATION": "满蓄力时间（秒）", "HIT_SCALE[1]": "碰撞和判定倍率", "SPEED[1]": "磁卫基础移速倍率", "SPEED[2]": "跃影基础移速倍率", "AI_MIN_CHARGE_SECONDS": "NPC 最短蓄力（秒）", "DASH_SPEED": "冲刺速度（米/秒）"}
for a in adjustments:
    for change in a["changes"]:
        lines.append(f"| 第 {a['after_round']} 场后 | {change['role']} | {labels[change['parameter']]} | {change['before']:g} → {change['after']:g} |")
lines += ["", "各组依据：", ""]
for a in adjustments:
    lines.append(f"- 第 {a['after_round']-1}～{a['after_round']} 场：{a['reason']}")
lines += ["", "## 最终参数与判断", "",
f"- 疾风：被动 +5% 移速；W {final_parameters['SPRINT_MULTIPLIER']:g} 倍疾跑，持续 2 秒，CD 10 秒。",
f"- 磁卫：判定尺寸 **+{(final_parameters['HIT_SCALE'][1]-1)*100:.0f}%**，基础移速 **-{(1-final_parameters['SPEED'][1])*100:.0f}%**；减速半径 **{final_parameters['SLOW_RADIUS']:g} 米**，减速 **{(1-final_parameters['SLOW_MULTIPLIER'])*100:.0f}%**，持续 5 秒，CD 20 秒。",
f"- 跃影：基础移速 **-{(1-final_parameters['SPEED'][2])*100:.0f}%**；可移动、带球蓄力，上限 **{final_parameters['CHARGE_DURATION']:g} 秒**，NPC 蓄力 {final_parameters['CHARGE_DURATION'] * final_parameters['AI_CHARGE_MIN_FRACTION']:g}～{final_parameters['CHARGE_DURATION']:g} 秒；冲刺 3～9 米，速度 **{final_parameters['DASH_SPEED']:g} 米/秒**，CD **{final_parameters['COOLDOWN'][2]:g} 秒**，不可储存。", "",
"跃影的正常进球从上轮 2 增至本轮 18，已能承担进攻，但还出现 4 个乌龙球。磁卫前四场仍很强，移速降低后进球明显减少，最后两场只有 1 球，因此最终回补一半移速惩罚。最后两场持球份额较接近，抢断与进球分工仍明显，不能据此宣布已达到稳定平衡。", "",
f"第 10 场后的最终移速回补未追加整场模拟。最终 {verification[1]} 项技能与统计行为检查通过，日志为 `work/balance-v2/abilities-final.log`；实际渲染的角色菜单、30% 减速提示、4 秒冷却与 0.6 秒蓄力说明已检查，渲染日志无错误。", "",
"## 数据与重跑", "", "- 汇总和逐球员明细：`work/balance-v2/balance-ten.json`。包含进球事件、角色参数快照、两队球衣号码与每名球员的统计。",
"- 每组原始数据和日志：`work/balance-v2/balance-batch-01.json` 至 `05.json`，以及同名 `.log`。",
"- 调整记录：`work/balance-v2/balance-adjustments.json`。上轮数据与报告保留在 `work/balance-ten.json` 和 `BALANCE_10.md`。",
"- `simulations/balance.gd` 每次运行 2 场；`--batch=1` 至 `--batch=5` 对应本次分组阵容与种子。重跑使用当前源码参数，复现历史组必须恢复该 JSON 的参数快照。默认会写回对应组的文件。",
"- `simulations/summarize_balance.py` 当前只汇总 `work/balance-v2/` 的 5 组数据，不运行比赛。", ""]
(ROOT / "BALANCE_10_V2.md").write_text("\n".join(lines), encoding="utf-8")
print("Validated: exactly 10 games; goal/score totals, possession clocks, tackle/turnover counts and swapped lineups reconcile.")
for t in totals:
    print(f"{t['name']}: n={t['appearances']}, forwards={t['forward_appearances']}, goals={t['goals']}, tackles={t['tackles']}, interceptions={t['interceptions']}, possession={t['possession_seconds']:.3f}s / {t['possession_percent']:.3f}%")
print(f"Loose ball: {loose:.3f}s / {loose/30:.3f}%")
print("Saved BALANCE_10_V2.md and work/balance-v2/balance-ten.json")
