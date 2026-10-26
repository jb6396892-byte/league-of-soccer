"""Inspect saved two-match equipment batches; build the final ten-match report."""
import json
import math
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
WORK = ROOT / "work/balance-roster"
numbers = [int(n) for n in sys.argv[1:]] or list(range(1, 6))
blocks = [json.loads((WORK / f"balance-batch-{n:02}.json").read_text(encoding="utf-8-sig")) for n in numbers]
games = [g for b in blocks for g in b["games"]]
rows = [p for g in games for p in g["players"]]
held = sum(p["stats"]["possession_seconds"] for p in rows)
roles = []
for kind, name in enumerate(["疾风", "刺猬", "月影", "旗帜", "铁闸"]):
    group = [p for p in rows if p["role"] == kind]
    field = [p for p in group if not p["goalkeeper"]]
    total = {"name": name, "appearances": len(group), "outfield_n": len(field),
             "forward_n": sum(p["shirt_number"] >= 10 for p in group)}
    total.update({k: sum(p["stats"][k] for p in group) for k in group[0]["stats"]})
    total["possession_percent"] = total["possession_seconds"] / held * 100
    total["outfield"] = {k: sum(p["stats"][k] for p in field) / max(1, len(field)) for k in group[0]["stats"]}
    total["mean_items"] = sum(len(p["inventory"]) for p in group) / len(group)
    total["mean_gold_left"] = sum(p["gold"] for p in group) / len(group)
    roles.append(total)
items = []
for item_id in range(10):
    group = [g["equipment"][item_id] for g in games]
    item = {"id": item_id, "name": group[0]["name"]}
    item.update({k: sum(row[k] for row in group) for k in group[0] if k != "name"})
    item["held_percent"] = item["possession_seconds"] / item["equipped_seconds"] * 100 if item["equipped_seconds"] else 0
    item["tackles_per_minute"] = item["tackles"] * 60 / item["equipped_seconds"] if item["equipped_seconds"] else 0
    purchases = [p for g in games for p in g["purchases"] if p["item"] == item_id]
    item["mean_buy_time"] = sum(p["time"] for p in purchases) / len(purchases) if purchases else None
    items.append(item)
for b in blocks:
    a, c = b["games"]
    assert [p["role"] for p in a["players"]] == [p["role"] for p in c["players"][11:] + c["players"][:11]]
    assert [p["build_variant"] for p in a["players"]] == [p["build_variant"] for p in c["players"][11:] + c["players"][:11]]
    for g in b["games"]:
        assert len(g["players"]) == 22
        assert [sum(p["role"] == k for p in g["players"]) for k in range(5)] == [5, 5, 5, 5, 2]
        assert all(p["goalkeeper"] == (p["role"] == 4) for p in g["players"])
        assert sum(p["stats"]["goals"] + p["stats"]["own_goals"] for p in g["players"]) == sum(g["score"])
        assert sum(p["stats"]["tackles"] for p in g["players"]) == sum(p["stats"]["turnovers"] for p in g["players"])
        assert math.isclose(sum(p["stats"]["possession_seconds"] for p in g["players"]) + g["loose_ball_seconds"], 300, abs_tol=1e-6)
        for p in g["players"]:
            paid = sum(t["cost"] for t in g["purchases"] if (t["team"], t["shirt_number"]) == (p["team"], p["shirt_number"]))
            assert p["gold"] == b["parameters"]["economy"]["start"] + p["stats"]["gold_earned"] - paid
            assert len(p["inventory"]) <= 4 and len(set(p["inventory"])) == len(p["inventory"])
print("Scores:", ", ".join(f"{g['round']}={g['score'][0]}:{g['score'][1]}" for g in games))
for r in roles:
    o = r["outfield"]
    print(f"{r['name']}: goals={r['goals']} forwards={r['forward_n']} own={r['own_goals']} tackles={r['tackles']} held={r['possession_percent']:.1f}% "
          f"field/person goals={o['goals']:.2f} tackles={o['tackles']:.2f} held={o['possession_seconds']:.1f}s "
          f"stuns={r['stuns']} saves={r['saves']} attempts={r['save_attempts']} casts={r['casts']} earned={o['gold_earned']:.0f} items={r['mean_items']:.2f} bank={r['mean_gold_left']:.0f}")
for i in items:
    print(f"{i['name']}: buys={i['buyers']} minutes={i['equipped_seconds']/60:.1f} goals={i['goals']} "
          f"tackles/min={i['tackles_per_minute']:.2f} held={i['held_percent']:.1f}% buytime={i['mean_buy_time']}")
if len(games) != 10:
    sys.exit(0)

adjustments = json.loads((WORK / "adjustments.json").read_text(encoding="utf-8"))
assert [a["after_round"] for a in adjustments] == [2, 4, 6, 8, 10]
gear_source = (ROOT / "scripts/equipment.gd").read_text(encoding="utf-8")
role_source = (ROOT / "scripts/archetypes.gd").read_text(encoding="utf-8")
final_items = json.loads(re.search(r"const ITEMS := ([\s\S]+?)\nconst NPC_BUILDS", gear_source)[1])
final_roles = {name: json.loads(re.search(rf"^const {name} := (.+)$", role_source, re.M)[1])
               for name in ["SPEED", "HIT_SCALE", "COOLDOWN", "SPRINT_MULTIPLIER", "SLOW_RADIUS", "CHARGE_DURATION", "DASH_MAX_DISTANCE", "DASH_SPEED", "THROW_RANGE", "THROW_SPEED", "THROW_RADIUS", "THROW_WINDUP", "STUN_SECONDS", "KEEPER_SLOW_RADIUS", "SAVE_REACH", "SAVE_WINDOW", "SAVE_COOLDOWN"]}
final_economy = {name: json.loads(re.search(rf"^const {name} := (.+)$", gear_source, re.M)[1])
                 for name in ["START_GOLD", "TACKLE_GOLD", "INTERCEPT_GOLD", "STUN_GOLD", "GOAL_GOLD", "TEAM_GOAL_GOLD", "POSSESSION_GOLD", "STIPEND_GOLD"]}
checks = {}
for name in ["abilities", "economy", "new-roles"]:
    match = re.search(r"RESULT: (\d+) checks, (\d+) failures", (WORK / f"{name}-final.log").read_text(encoding="utf-8"))
    assert match and int(match[2]) == 0
    checks[name] = int(match[1])
result = {"games": games, "blocks": [{"batch": b["batch"], "parameters": b["parameters"]} for b in blocks],
          "roles": roles, "items": items, "adjustments": adjustments,
          "final_items": final_items, "final_roles": final_roles, "final_economy": final_economy, "checks": checks,
          "final_adjustment_full_match_validated": False}
(WORK / "balance-ten.json").write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding="utf-8")
lines = ["# 五角色补丁：10 场角色与装备平衡模拟", "",
         "2026-10-20。共 10 场，每场 300 秒有效比赛时间、60 Hz，22 人使用游戏内 NPC、经济和商店逻辑。每两场分析并调整一次，共五组。开场与进球后的 15 秒购买时间不计比赛时间。", "",
         "每组采用 5/5/5/5 的四种非门将职业阵容，另有两位固定铁闸门将，第二场交换两队对应位置的职业、出装路线与开球方。种子 9100–9109。每职业三条路线，让十件装备都有样本；NPC 与玩家同价同收入，保留反应延迟、瞄准误差和同角色同跑速。", "",
         "## 累计角色数据", "",
         "控球率以所有球员的实际持球时间为分母，自由球另计。以下合计包含五个不同参数版本，不能当作最终配置的十场验证。", "",
         "| 角色 | 出场/前锋人次 | 进球 | 乌龙 | 抢断 | 拦截 | 控球率 | 眩晕命中 | 扑救接获 | 平均装备数 |",
         "| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |"]
for r in roles:
    lines.append(f"| {r['name']} | {r['appearances']}/{r['forward_n']} | {r['goals']} | {r['own_goals']} | {r['tackles']} | {r['interceptions']} | {r['possession_percent']:.1f}% | {r['stuns']} | {r['saves']} | {r['mean_items']:.2f} |")
lines += ["", "每位外场角色累计出场 50 人次，门将 20 人次。蓝队与珊瑚队各赢 4 场，平局 2 场。刺猬占 20/40 个前锋人次，疾风只有 4/40，不能用总进球或控球率直接判断角色胜率；不用门将进球数与前锋直接比较。扑救计对方触球后以大于 5 米/秒速度来球的接获，含常规接球与 Q 扩展范围扑救，不包括挡开球；W 眩晕不计作抢断。", "",
          "| 场次 | 蓝队 : 珊瑚队 | 角色进球（疾风/刺猬/月影/旗帜/铁闸） | 抢断 | 控球率 |", "| --- | --- | --- | --- | --- |"]
for g in games:
    rs = g["roles"]
    possession = " / ".join(f"{r['possession_percent']:.1f}%" for r in rs)
    lines.append(f"| {g['round']} | {g['score'][0]} : {g['score'][1]} | {' / '.join(str(int(r['goals'])) for r in rs)} | {' / '.join(str(int(r['tackles'])) for r in rs)} | {possession} |")
lines += ["", "## 装备实战数据", "",
          "按实际穿戴的有效比赛时间统计，只记录购买后的进球、抢断、控球。穿多件装备时同一表现会同时计入多件，不能相加，亦不代表装备独立贡献。出装路线、职业、位置和经济领先均会影响结果，这不是因果胜率。", "",
          "| 装备 | 购买人次 | 穿戴分钟 | 穿戴期间进球 | 每分钟抢断 | 穿戴时间中的控球率 |", "| --- | ---: | ---: | ---: | ---: | ---: |"]
for i in items:
    lines.append(f"| {i['name']} | {i['buyers']} | {i['equipped_seconds']/60:.1f} | {i['goals']} | {i['tackles_per_minute']:.2f} | {i['held_percent']:.1f}% |")
lines += ["", "## 每两场调整", ""]
for a in adjustments:
    lines += [f"### 第 {a['after_round']} 场后", "", a["reason"], ""]
    lines.extend(f"- {c}" for c in a["changes"])
    lines.append("")
lines += ["## 最终装备", "", "| 装备 | 金钱 | 效果 |", "| --- | ---: | --- |"]
for i in final_items:
    lines.append(f"| {i['name']} | {i['cost']} | {'；'.join(i['lines'])} |")
lines += ["", f"最终角色移速倍率：{final_roles['SPEED']}；判定倍率：{final_roles['HIT_SCALE']}；W 基础冷却：{final_roles['COOLDOWN']}。疾风基础疾跑倍率为 {final_roles['SPRINT_MULTIPLIER']}。其余参数与各组完整快照见 JSON。",
          f"初始金仍为500；抢断50、拦截25、进球300/全队60、累计控球5秒20金保持。全员津贴为每15秒 {final_economy['STIPEND_GOLD']} 金。新增旗帜眩晕命中20金是第十场后补偿，未计入本轮收入数据。", "",
          f"实际验证：{checks['abilities']} 项技能/AI 检查、{checks['economy']} 项经济检查、{checks['new-roles']} 项新角色检查通过。所有十场均核对比分与进球归属、抢断与丢球、有效时间、阵容互换和逐球员金钱收支。第十场后的调整未追加第十一场，仍需后续试玩。", "",
          "设计参考：[Riot 的技能清晰度说明](https://www.leagueoflegends.com/en-us/news/dev/clarity-in-league/)与[反制设计说明](https://www.leagueoflegends.com/en-gb/news/dev/quick-gameplay-thoughts-may-14/)。本作据此采用独立轮廓、可见范围、施法预警与可躲避弹体；形象及代码均为本 demo 原创。", "",
          "原始数据：`work/balance-roster/balance-batch-01.json` 至 `05.json`；完整汇总：`work/balance-roster/balance-ten.json`；每组日志同目录。历史报告与数据保留。"]
(ROOT / "BALANCE_FIVE_ROLES_10.md").write_text("\n".join(lines) + "\n", encoding="utf-8")
print("Saved BALANCE_FIVE_ROLES_10.md and work/balance-roster/balance-ten.json")
