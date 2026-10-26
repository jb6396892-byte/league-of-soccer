"""Inspect saved two-match evolution blocks; report the completed ten matches."""
import json
import math
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
WORK = ROOT / "work/balance-evolution"
numbers = [int(n) for n in sys.argv[1:]] or list(range(1, 6))
blocks = [json.loads((WORK / f"balance-batch-{n:02}.json").read_text(encoding="utf-8-sig")) for n in numbers]
games = [g for b in blocks for g in b["games"]]
rows = [p for g in games for p in g["players"]]
held = sum(p["stats"]["possession_seconds"] for p in rows)
roles = []
for kind, name in enumerate(["疾风", "刺猬", "月影", "旗帜", "铁闸"]):
    group = [p for p in rows if p["role"] == kind]
    total = {"name": name, "appearances": len(group),
             "forwards": sum(p["shirt_number"] >= 10 for p in group)}
    total.update({key: sum(p["stats"][key] for p in group) for key in group[0]["stats"]})
    total["possession_percent"] = total["possession_seconds"] / held * 100
    total["mean_income"] = total["gold_earned"] / len(group)
    total["mean_items"] = sum(len(p["inventory"]) for p in group) / len(group)
    roles.append(total)
flags = [p for p in rows if p["role"] == 3]
milestones = []
for index, threshold in enumerate([5, 10]):
    times = [p["evolution_times"][index] for p in flags if p["evolution_times"][index] >= 0]
    milestones.append({"hits": threshold, "reached": len(times), "appearances": len(flags),
                       "mean_time": sum(times) / len(times) if times else None})
items = []
for item_id in range(len(games[0]["equipment"])):
    group = [g["equipment"][item_id] for g in games]
    item = {"id": item_id, "name": group[0]["name"]}
    item.update({key: sum(r[key] for r in group) for key in group[0] if key != "name"})
    purchases = [p for g in games for p in g["purchases"] if p["item"] == item_id]
    item["purchases"] = len(purchases)
    item["mean_buy_time"] = sum(p["time"] for p in purchases) / len(purchases) if purchases else None
    item["held_percent"] = item["possession_seconds"] / item["equipped_seconds"] * 100 if item["equipped_seconds"] else 0
    items.append(item)

for block in blocks:
    first, second = block["games"]
    for key in ["role", "build_variant"]:
        assert [p[key] for p in first["players"]] == [p[key] for p in second["players"][11:] + second["players"][:11]]
    for g in block["games"]:
        assert [sum(p["role"] == k for p in g["players"]) for k in range(5)] == [5, 5, 5, 5, 2]
        assert [sum(p["role"] == k and p["shirt_number"] >= 10 for p in g["players"]) for k in range(4)] == [1, 1, 1, 1]
        assert all(p["goalkeeper"] == (p["role"] == 4) for p in g["players"])
        assert sum(p["stats"]["goals"] + p["stats"]["own_goals"] for p in g["players"]) == sum(g["score"])
        assert sum(p["stats"]["tackles"] for p in g["players"]) == sum(p["stats"]["turnovers"] for p in g["players"])
        assert math.isclose(sum(p["stats"]["possession_seconds"] for p in g["players"]) + g["loose_ball_seconds"], 300, abs_tol=1e-6)
        for p in g["players"]:
            bought = [t for t in g["purchases"] if (t["team"], t["shirt_number"]) == (p["team"], p["shirt_number"])]
            assert p["gold"] == block["parameters"]["economy"]["start"] + p["stats"]["gold_earned"] - sum(t["cost"] for t in bought)
            assert p["team_purchases"] == [sum(t["item"] == item for t in bought) for item in [12, 13]]
            assert len(p["inventory"]) <= 4 and len(p["inventory"]) == len(set(p["inventory"]))
            assert all(i < 12 for i in p["inventory"])
            if g["round"] >= 5:
                personal_count = 0
                for purchase in bought:
                    if purchase["item"] < 12:
                        personal_count += 1
                    else:
                        assert personal_count == 4, "NPC must complete four personal items before team upgrades"
        for team in range(2):
            expected = [sum(t["item"] == item and t["team"] == team for t in g["purchases"]) for item in [12, 13]]
            assert expected == g["team_upgrades"][team]
            speed = 1.02 ** g["team_upgrades"][team][0] * 0.98 ** g["team_upgrades"][1 - team][1]
            assert math.isclose(speed, g["team_speed"][team], abs_tol=1e-6)
        assert block["parameters"]["stun_upgrade_hits"] == 5 and block["parameters"]["mobile_throw_hits"] == 10
        assert block["parameters"]["stun_upgrade_bonus"] == 1.5
        assert all(block["parameters"]["items"][i]["cost"] == 800 for i in [12, 13])

print("Scores:", ", ".join(f"{g['round']}={g['score'][0]}:{g['score'][1]}" for g in games))
for r in roles:
    print(f"{r['name']}: goals={r['goals']} tackles={r['tackles']} held={r['possession_percent']:.1f}% "
          f"stuns={r['stuns']} stun_added={r['stun_seconds']:.1f}s casts={r['casts']} saves={r['saves']} "
          f"income={r['mean_income']:.0f} items={r['mean_items']:.2f} forwards={r['forwards']}")
print("Evolution:", milestones)
for item in items:
    time = f"{item['mean_buy_time']:.1f}s" if item["mean_buy_time"] is not None else "none"
    print(f"{item['name']}: buys={item['purchases']} minutes={item['equipped_seconds']/60:.1f} goals={item['goals']} "
          f"stuns={item['stuns']} saves={item['saves']} held={item['held_percent']:.1f}% first_mean={time}")
if len(games) != 10:
    sys.exit(0)

adjustments = json.loads((WORK / "adjustments.json").read_text(encoding="utf-8"))
assert [a["after_round"] for a in adjustments] == [2, 4, 6, 8, 10]
gear_source = (ROOT / "scripts/equipment.gd").read_text(encoding="utf-8")
role_source = (ROOT / "scripts/archetypes.gd").read_text(encoding="utf-8")
final_items = json.loads(re.search(r"const ITEMS := ([\s\S]+?)\nconst NPC_BUILDS", gear_source)[1])
constant_names = ["SPEED", "COOLDOWN", "SPRINT_MULTIPLIER", "HIT_WIDTH_GROWTH", "HIT_SPEED_GROWTH", "THROW_RADIUS", "THROW_SPEED",
                  "THROW_RANGE", "THROW_WINDUP", "STUN_SECONDS", "STUN_UPGRADE_BONUS", "SAVE_WINDOW", "SAVE_REACH"]
final_roles = {name: json.loads(re.search(rf"^const {name} := (.+)$", role_source, re.M)[1]) for name in constant_names}
checks = {}
for name in ["abilities", "economy", "new-roles", "evolution"]:
    match = re.search(r"RESULT: (\d+) checks, (\d+) failures", (WORK / f"{name}-final.log").read_text(encoding="utf-8"))
    assert match and int(match[2]) == 0
    checks[name] = int(match[1])
result = {"games": games, "blocks": [{"batch": b["batch"], "parameters": b["parameters"]} for b in blocks],
          "roles": roles, "milestones": milestones, "items": items, "adjustments": adjustments,
          "final_roles": final_roles, "final_items": final_items, "checks": checks,
          "final_adjustment_full_match_validated": False}
(WORK / "balance-ten.json").write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding="utf-8")
lines = ["# 旗帜成长、专属装备与全队升级：10 场平衡记录", "",
         "2026-10-20。10 场，每场 300 秒有效时间、60 Hz、22 名 NPC，按每两场调整一次完成五组。使用游戏内技能、反应延迟、商店与经济，未给测试队伍额外金钱。购买时间不计比赛时长。", "",
         "四种外场角色每场各 5 人，另有 2 位固定门将。每场四个前锋位置各分配一种外场角色，第二场交换两队职业、位置和出装路线；全程每种外场角色均 50 人次、10 个前锋人次。种子 10100–10109。", "",
         "以下统计混合五个参数版本，不能当作最终配置的十场验证，也不能推出单角色或单装备的因果胜率。控球率以球员实际持球时间为分母，自由球另计。", "",
         "| 角色 | 进球 | 乌龙 | 抢断 | 拦截 | 控球率 | 眩晕命中 | 人均收入 |",
         "| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |"]
for r in roles:
    lines.append(f"| {r['name']} | {r['goals']} | {r['own_goals']} | {r['tackles']} | {r['interceptions']} | {r['possession_percent']:.1f}% | {r['stuns']} | {r['mean_income']:.0f} |")
lines += ["", "## 旗帜进化", "", "第 5 次命中解锁后续 W 额外 1.5 秒眩晕；第 10 次解锁移动前摇。每次命中只叠一层，每次施法按施放时层数固定弹体参数。", "",
          "| 门槛 | 达成人次 / 旗帜人次 | 达成者平均时间 |", "| --- | ---: | ---: |"]
for m in milestones:
    time = f"{m['mean_time']:.1f} 秒" if m["mean_time"] is not None else "未达成"
    lines.append(f"| {m['hits']} 次命中 | {m['reached']} / {m['appearances']} | {time} |")
lines += ["", "## 逐场比分与全队升级", "",
          "进化之靴与虚弱之镰均 800 金，可重复、不占栏，本场永久。每队最终速度倍率 = 1.02^本队购靴次数 × 0.98^敌队购镰次数。下表次数均为实际扣费购买。", "",
          "购买策略在途中更改：第1–2场有一条路线先买2件个人装，第3–4场先买1件；用户随后指定先出满四件，第5–10场所有NPC统一买齐4件个人装再攒800金。前4场保留为旧策略数据，不能当作最终购买策略的表现。", "",
          "| 场次 | 比分 蓝:珊瑚 | 角色进球：疾风/刺猬/月影/旗帜/铁闸 | 蓝队 靴/镰 | 珊瑚 靴/镰 | 最终队速 蓝/珊瑚 |",
          "| --- | --- | --- | --- | --- | --- |"]
for g in games:
    goals = "/".join(str(int(r["goals"])) for r in g["roles"])
    a, b = g["team_upgrades"]
    lines.append(f"| {g['round']} | {g['score'][0]}:{g['score'][1]} | {goals} | {a[0]}/{a[1]} | {b[0]}/{b[1]} | {g['team_speed'][0]:.3f}/{g['team_speed'][1]:.3f} |")
lines += ["", "## 装备表现", "", "仅统计买入后实际穿戴期间的表现。穿多件装备会重复归属同一表现，不能相加。全队升级没有装备栏穿戴时间，单列交易次数。", "",
          "| 装备 | 购买次数 | 穿戴分钟 | 进球 | 抢断 | 眩晕命中 | 扑救接获 | 控球占穿戴时间 |",
          "| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |"]
for i in items[:12]:
    lines.append(f"| {i['name']} | {i['purchases']} | {i['equipped_seconds']/60:.1f} | {i['goals']} | {i['tackles']} | {i['stuns']} | {i['saves']} | {i['held_percent']:.1f}% |")
late_team_buys = [sum(p["item"] == item for g in games if g["round"] >= 5 for p in g["purchases"]) for item in [12, 13]]
lines += ["", f"进化之靴共购买 {items[12]['purchases']} 次；虚弱之镰共购买 {items[13]['purchases']} 次。门将扑救接获统计为接到对方最后触球、速度大于 5 米/秒的球，不包含挡开。", "",
          f"其中，第5–10场采用用户指定的四件个人装优先策略，进化之靴 {late_team_buys[0]} 次、虚弱之镰 {late_team_buys[1]} 次。该策略下升级更偏后期，当前5分钟样本不足以判断大量叠加后的长期平衡。重复扣费与阵营倍率另有行为检查。", "",
          "## 每两场调整", ""]
for a in adjustments:
    lines += [f"### 第 {a['after_round']} 场后", "", a["reason"], ""]
    lines.extend(f"- {change}" for change in a["changes"])
    lines.append("")
lines += ["## 最终新装备", "", "| 装备 | 金钱 | 效果 |", "| --- | ---: | --- |"]
for i in final_items[10:]:
    lines.append(f"| {i['name']} | {i['cost']} | {'；'.join(i['lines'])} |")
lines += ["", f"旗帜最终每次命中增加基础宽度 {final_roles['HIT_WIDTH_GROWTH']*100:g}%、基础弹速 {final_roles['HIT_SPEED_GROWTH']*100:g}%；基础弹速 {final_roles['THROW_SPEED']:g} 米/秒，W 冷却 {final_roles['COOLDOWN'][3]:g} 秒。保留初始移速 -5%，进球不再加速。", "",
          f"最终检查：{checks['abilities']} 项原技能/AI、{checks['economy']} 项经济、{checks['new-roles']} 项新角色、{checks['evolution']} 项成长及全队装备检查通过。十场已核对角色和前锋分配、比分、球权时间、抢断/丢球、逐人金钱收支、全队购买次数与速度倍率。第十场后修改未追加第十一场。", "",
          "成长门槛设计参考 [Smolder 官方技能说明](https://www.leagueoflegends.com/en-us/event/smolder-abilities-rundown/)和 [Syndra 官方说明](https://www.leagueoflegends.com/en-au/champions/syndra/)；不占栏永久升级参考 [Dota 2 6.84 的 Moon Shard 消耗设计](https://www.dota2.com/684?l=english)。本作数值、规则与实现均为原创，不复制其素材或代码。", "",
          "原始数据位于 `work/balance-evolution/balance-batch-01.json` 至 `05.json`，完整汇总为同目录 `balance-ten.json`；以前的模拟数据保留。"]
(ROOT / "BALANCE_EVOLUTION_10.md").write_text("\n".join(lines) + "\n", encoding="utf-8")
print("Saved BALANCE_EVOLUTION_10.md and work/balance-evolution/balance-ten.json")
