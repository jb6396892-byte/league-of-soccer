"""Validate the saved 20-game campaign and write its report; never runs matches."""
import json
import re
import statistics
from collections import Counter, defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DATA = ROOT / "work" / "balance-hard"
config = json.loads((DATA / "configuration-01.json").read_text(encoding="utf-8"))
games = [json.loads(p.read_text(encoding="utf-8")) for p in sorted(DATA.glob("match-*.json"))]
assert [g["round"] for g in games] == list(range(1, len(games) + 1))
assert len(games) <= 20 and len(games) % 2 == 0
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
    assert game["difficulty"] == 2 and config["difficulty"] == 2
    assert all(e["result"] != "holding" for e in game["keeper"])
    assert sum(e["saved"] for e in game["keeper"]) == sum(p["stats"]["saves"] for p in game["players"])
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


passes = [p for g in games for p in g['passes']]
q = [p for g in games for p in g['q_actions']]
for g in games:
    assert sum(len(g[k]) for k in ('passes', 'q_actions')) == sum(p['stats']['kicks'] for p in g['players'])
    assert all(p['result'] != 'pending' for p in g['passes'])
    for team in range(2):
        assert abs(sum(g['phases'][team].values()) - g['seconds']) < 0.05
summary = {'games':len(games), 'scores':[g['score'] for g in games],
    'wins':[sum(g['score'][t]>g['score'][1-t] for g in games) for t in (0,1)],
    'seconds':sum(g['seconds'] for g in games), 'overtimes':sum(g['overtime']>0 for g in games),
    'passes':len(passes), 'complete':sum(p['result']=='complete' for p in passes),
    'pass_kinds':{k:dict(Counter(p['result'] for p in passes if p['kind']==k)) for k in sorted(set(p['kind'] for p in passes))},
    'q_kinds':dict(Counter(p['kind'] for p in q)),
    'q_lines':dict(Counter(p['line'] for p in q if p['contested'])),
    'goals_by_role':[sum(p['stats']['goals'] for g in games for p in g['players'] if p['role']==r) for r in range(6)],
    'item_buys':[x['purchases'] for x in item_totals],
    'pair':[]}
phase_totals=Counter()
for g in games:
    for team in g['phases']:
        phase_totals.update(team)
summary['phase_seconds']=dict(phase_totals)
for first,second in zip(games[::2], games[1::2]):
    ps=first['passes']+second['passes']; qs=first['q_actions']+second['q_actions']
    summary['pair'].append({'rounds':[first['round'],second['round']], 'scores':[first['score'],second['score']],
        'seconds':first['seconds']+second['seconds'], 'passes':len(ps),'complete':sum(p['result']=='complete' for p in ps),
        'kind':{k: [sum(p['kind']==k for p in ps),sum(p['kind']==k and p['result']=='complete' for p in ps)] for k in sorted(set(p['kind'] for p in ps))},
        'q':dict(Counter(p['kind'] for p in qs)), 'results':dict(Counter(p['result'] for p in ps)),
        'q_lines':dict(Counter(p['line'] for p in qs if p['contested']))})
(DATA/'summary.json').write_text(json.dumps(summary,ensure_ascii=False,indent=2),encoding='utf-8')
print(json.dumps({'games':len(games),'last_pair':summary['pair'][-1], 'total_complete': [summary['complete'],summary['passes']], 'q':summary['q_kinds']},ensure_ascii=False))

keeper = [e for g in games for e in g['keeper']]
saved = [e for e in keeper if e['saved']]
released = [e for e in keeper if e['result'] == 'released']
summary['keeper'] = {'holds':len(keeper), 'results':dict(Counter(e['result'] for e in keeper)),
	'tackle_losses':sum(p['stats']['turnovers'] for g in games for p in g['players'] if p['goalkeeper']),
    'saves':len(saved), 'save_results':dict(Counter(e['result'] for e in saved)),
    'mean_release':statistics.mean(e['seconds'] for e in released),
    'max_release':max(e['seconds'] for e in released),
    'p95_release':sorted(e['seconds'] for e in released)[int((len(released)-1)*.95)],
    'long_holds':sum(e['seconds'] > 2 for e in keeper)}
summary['skill_totals'] = [dict(x) for x in skill_totals]
(DATA/'summary.json').write_text(json.dumps(summary,ensure_ascii=False,indent=2),encoding='utf-8')
print(json.dumps({'keeper':summary['keeper']},ensure_ascii=False))

if len(games) == 20:
    history = json.loads((DATA/'adjustments.json').read_text(encoding='utf-8'))
    assert [h['after'] for h in history] == list(range(2,21,2))
    assert not history[-1]['changes'], 'Final changes require a fresh final configuration snapshot.'
    final = json.loads((DATA/'configuration-10.json').read_text(encoding='utf-8'))
    for batch in range(5,11):
        snapshot = json.loads((DATA/f'configuration-{batch:02}.json').read_text(encoding='utf-8'))
        assert all(snapshot[key] == final[key] for key in ('items','skills','profiles','npc_tactics'))
    (DATA/'configuration-final.json').write_text(json.dumps(final,ensure_ascii=False,indent=2),encoding='utf-8')
    stable = [e for g in games[8:] for e in g['keeper']]
    stable_released = [e for e in stable if e['result']=='released']
    stable_passes = [e for g in games[8:] for e in g['passes'] if e['kind']=='keeper_outlet']
    summary['final_configuration'] = {'games':12, 'holds':len(stable), 'released':len(stable_released),
        'results':dict(Counter(e['result'] for e in stable)),
        'mean_release':statistics.mean(e['seconds'] for e in stable_released),
        'max_release':max(e['seconds'] for e in stable_released),
        'outlets':len(stable_passes), 'completed':sum(e['result']=='complete' for e in stable_passes)}
    (DATA/'summary.json').write_text(json.dumps(summary,ensure_ascii=False,indent=2),encoding='utf-8')
    k = summary['keeper']
    lines = ['# 门将出球与困难 AI：20 场平衡测试', '',
        '2026-10-22。20 场新比赛，10 组镜像阵容/出装/开球对抗；红队困难、蓝队一般，每场常规 5 分钟。平局继续完整 120 秒加时，直到该段结束有胜负。难度只改变决策参数，不增加金币或跑速。', '',
        f"完成 {summary['seconds']/60:.0f} 分钟有效比赛，蓝队 {summary['wins'][0]} 胜、困难红队 {summary['wins'][1]} 胜，{summary['overtimes']} 场加时，共 {sum(sum(g['score']) for g in games)} 球。共检查 10 次，其中 {sum(bool(h['changes']) for h in history)} 次实际修改，其余保留配置。", '',
        '## 门将修复', '',
        '接住球后结束扑救动作，剩余出球恢复最多 0.2 秒；NPC 在恢复期间观察线路并转身，冷却结束且朝向对准才实际出脚。优先选择无阻挡、附近有空间的接应者；没有安全线路时斜向挑球解围。扑空仍保留原 1.5 秒冷却，球权保护不额外延长。', '',
        '门将出球避开沿途队友，也不再于出脚恢复期吸回自己的球；其他球员仍可拦截。补给暂停冻结相关计时。', '',
        f"日志共记录 {k['holds']} 次门将取得球权，{len(released)} 次实际出球、{len(keeper)-len(released)} 次未出球终止；其中记录扑救 {k['saves']} 次，包含第 7 场修复前的两条边界错误，详见下文。成功出球平均 {k['mean_release']:.2f} 秒，95% 分位 {k['p95_release']:.2f} 秒，最长 {k['max_release']:.2f} 秒；所有持球中超过 2 秒的记录 {k['long_holds']} 次。", '',
        '出球指球真正离脚，不等同于传球成功。门将短传和其他配合均以指定接应者实际获得球权统计完成率；反弹和其他队友捡球分开记录。', '',
        f"门将实际被贴身抢断合计 {k['tackle_losses']} 次。第 7 场有两次 0 秒持球中止，来自已越界来球仍判接球的旧错误，其中一次错误归为门将乌龙；第 8 场后已修复，历史记录保留。`lost` 表示球权中止，不一概视为被抢断。", '',
        f"最终配置保持了第 9–20 场共 12 场：门将 {len(stable)} 次持球、{len(stable_released)} 次实际出球，出球平均 {summary['final_configuration']['mean_release']:.2f} 秒、最长 {summary['final_configuration']['max_release']:.2f} 秒；安全短传 {summary['final_configuration']['completed']}/{len(stable_passes)} 完成。这是固定配置的描述性样本，不是与旧版的同种子对照。", '',
        '## 足球辨识度', '',
        '足球使用不受灯光影响的黑白材质；真实投影位置上增加黑白球形标记、金色外圈和小箭头，显示层高于 3D 技能特效。大小在远近镜头下有上下限，跟随球的真实高度；商店、暂停和帮助页隐藏，球的物理尺寸不变。', '',
        '实际 GPU 截图：`work/keeper-dense-effects.png`、`keeper-air-ball.png`、`keeper-overview.png`、`keeper-shop.png`。', '',
        '## 每两场的结果', '', '| 场次 | 比分（蓝:困难红） | 秒数 | 门将出球/持球 | 未出球终止 | 接应/短传 |', '| --- | --- | ---: | ---: | ---: | ---: |']
    for a,b in zip(games[::2],games[1::2]):
        events = a['keeper'] + b['keeper']
        outlets = [p for g in (a,b) for p in g['passes'] if p['kind']=='keeper_outlet']
        scores = ' / '.join(':'.join(map(str,g['score'])) for g in (a,b))
        lines.append(f"| {a['round']}–{b['round']} | {scores} | {a['seconds']+b['seconds']:.0f} | {sum(e['result']=='released' for e in events)}/{len(events)} | {sum(e['result']!='released' for e in events)} | {sum(e['result']=='complete' for e in outlets)}/{len(outlets)} |")
    lines += ['', '## 调整记录', '', '| 场后 | 根据与决定 |', '| --- | --- |']
    for entry in history:
        lines.append(f"| {entry['after']} | {entry['reason']} |")
    lines += ['', '数值的逐项旧值/新值及实现修正在 `work/balance-hard/adjustments.json`，各组开赛配置单独保存。', '',
        '## 装备与技能使用', '', '| 装备 | 最终价格 | 购买次数（含材料） |', '| --- | ---: | ---: |']
    for item,count in zip(final['items'],summary['item_buys']):
        lines.append(f"| {item['name']} | {item['cost']} | {count} |")
    lines += ['', '| E 技能 | 最终单次价格 | 购买 | 使用 |', '| --- | ---: | ---: | ---: |']
    for item,counts in zip(final['skills'],skill_totals):
        lines.append(f"| {item['name']} | {item['cost']} | {counts['bought']} | {counts['casts']} |")
    lines += ['', f"装备购买覆盖 {sum(x > 0 for x in summary['item_buys'])}/{len(items)} 件。每队每种外场角色两人加一名门将，镜像轮换三条出装路线；购买率受到预设路线影响，不能据此宣称每件装备性价比已完全均衡。", '',
        '## 检查与局限', '',
        f'- 使用实际比赛代码与 60 Hz 物理。已核对 {wallets} 名球员的金币、配方、六格装备、E 次数及消耗；进球、抢断、控球时间、传球/Q 事件与门将扑救事件均核对。',
        '- 这是跨多个配置的自适应测试，不是旧版/新版的同种子因果比较；也不能把困难队胜率直接当作真人玩家胜率。',
        '- 双方为 NPC，针对真人的封线规则另由已有设置测试检查，完整比赛不能替代真人难度试玩。',
        '- 实际通过 353 项相关检查：门将 27、NPC 战术 48、装备/E 73、新角色 41、设置/补给 53、经济 38、模式/教程 73。日志为 `work/keeper-test.log`、`work/hard-final-*.log`。GPU 预览实际运行并目视检查密集特效、空中球与全场镜头，`work/keeper-preview.log` 无脚本错误。', '',
        '数据保留在 `work/balance-hard/`；运行入口 `simulations/balance_hard.gd --batch=1..10` 拒绝覆盖已完成场次，`simulations/summarize_hard.py` 只校验并汇总保存的数据。', '',
        '设计参考：[Riot Clarity in League](https://www.leagueoflegends.com/en-us/news/dev/clarity-in-league/) 的视觉层级原则，以及 [EA FC 25 Gameplay Deep Dive](https://www.ea.com/games/ea-sports-fc/fc-25/news/pitch-notes-fc-25-gameplay-deep-dive) 的角色职责与传球设计。本项目实现和素材均为原创。', '']
    (ROOT/'BALANCE_HARD_20.md').write_text('\n'.join(lines),encoding='utf-8')

