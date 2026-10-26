"""Validate the saved 30-game campaign and write its report; never runs matches."""
import json
import re
import statistics
from collections import Counter, defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DATA = ROOT / "work" / "balance-npc"
config = json.loads((DATA / "configuration-01.json").read_text(encoding="utf-8"))
games = [json.loads(p.read_text(encoding="utf-8")) for p in sorted(DATA.glob("match-*.json"))]
assert [g["round"] for g in games] == list(range(1, len(games) + 1))
assert len(games) <= 30 and len(games) % 2 == 0
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

if len(games) == 30:
    history = json.loads((DATA/'adjustments.json').read_text(encoding='utf-8'))
    reviews = len(history)
    revisions = sum(bool(entry['changes'] or entry['logic']) for entry in history)
    stable_passes = sum(pair['passes'] for pair in summary['pair'][-4:])
    stable_complete = sum(pair['complete'] for pair in summary['pair'][-4:])
    tune = json.loads(re.search(r'const TUNE := (\{.*?\})', (ROOT/'scripts/npc_tactics.gd').read_text(encoding='utf-8'), re.S)[1])
    final = json.loads((DATA/'configuration-15.json').read_text(encoding='utf-8'))
    final['npc_tactics'] = tune
    (DATA/'configuration-final.json').write_text(json.dumps(final,ensure_ascii=False,indent=2),encoding='utf-8')
    names = {'pass':'普通接应','one_two':'二过一起手','return':'二过一回做','through':'直塞','cross':'低平传中','cutback':'倒三角','recycle':'回传重组','overlap':'套边接力'}
    lines = ['# NPC 战术：30 场对抗与逐组优化', '',
        '完成日期：2026-10-22。共 30 场新比赛，15 组镜像对抗；一般难度、每场常规 5 分钟，平局继续完整 2 分钟加时直至分胜负。每两场检查实际数据再决定调整。旧比赛及原始报告不覆盖。', '',
        f"累计有效比赛时间 {summary['seconds']/60:.0f} 分钟，蓝方 {summary['wins'][0]} 胜、红方 {summary['wins'][1]} 胜，{summary['overtimes']} 场进入加时，共 {sum(sum(g['score']) for g in games)} 球。", '',
        f"指定接应成功 {summary['complete']}/{summary['passes']}（{summary['complete']/summary['passes']:.1%}）。这里只把预定接应者实际取得球权算成功；其他队友捡球单独记录，碰到球并不等于成功。", '',
        f"共 {reviews} 次逐组检查、{revisions} 次功能或平衡修正。第 23–30 场保持相同全 NPC 逻辑，接应成功 {stable_complete}/{stable_passes}（{stable_complete/stable_passes:.1%}）；第 28 场后的补齐只影响玩家回传门将。此处为 8 场描述性样本，不是因果对照试验。", '',
        '## 已实现的行为', '',
        '- 传球出脚后观察实际轨迹，队友主动转身、移动接球；近距离高速友方球允许一次真实接触后的缓冲，仍是可被争抢的自由球。',
        '- 后卫优先 Q 解围和干扰，中场、前锋也会尝试；有范围、高度、冷却和反应延迟，机会消失会取消。前锋受压时在合理角度提前射门。',
        '- 全局短传推进、边路展开、夺回球权后反击、末段领先控球、落后压迫；局部二过一、直塞、套边、低平传中、倒三角和安全回传。', '',
        '## 战术实测', '', '| 配合 | 实际出球 | 指定接应成功 | 完成率 |', '| --- | ---: | ---: | ---: |']
    for kind, counts in summary['pass_kinds'].items():
        total=sum(counts.values()); complete=counts.get('complete',0)
        lines.append(f"| {names.get(kind,kind)} | {total} | {complete} | {complete/total:.1%} |")
    lines += ['', '二过一起手和回做分别统计；起手成功不等于打穿防线。传中按地面接球实现，本版本没有头球系统。套边出球只在同侧后卫实际超越持球者后记录，普通边路回传不冒充套边。', '',
        '| 全局阶段 | 双方累计秒数 |', '| --- | ---: |']
    for phase,label in [('build','短传推进'),('wide','边路展开'),('counter','球权转换反击'),('protect','领先控制'),('press','落后压迫')]:
        lines.append(f'| {label} | {phase_totals[phase]:.1f} |')
    lines += ['', '阶段时间包含有球与无球职责，两个队分别累计；不把阶段时间直接称为成功进攻。', '',
        '| Q 行为 | 次数 |','| --- | ---: |']
    qnames={'shot':'常规射门','pressure_shot':'受压抢射','clearance':'解围','volley':'无球抢射'}
    for kind,count in summary['q_kinds'].items():
        lines.append(f'| {qnames.get(kind,kind)} | {count} |')
    lines += ['', '无球争抢实际出脚按位置统计：' + '，'.join(f'{name} {summary["q_lines"].get(line,0)} 次' for line,name in [(1,'后卫'),(2,'中场'),(3,'前锋')]) + '。这是实际出脚数，受出场位置和机会影响，不是单次尝试概率。', '',
        '## 15 组结果', '', '| 场次 | 比分 | 有效秒数 | 接应成功 / 传球 |', '| --- | --- | ---: | ---: |']
    for pair in summary['pair']:
        score=' / '.join(':'.join(map(str,x)) for x in pair['scores'])
        lines.append(f"| {pair['rounds'][0]}–{pair['rounds'][1]} | {score} | {pair['seconds']:.0f} | {pair['complete']}/{pair['passes']} |")
    lines += ['', '## 调整记录', '', '| 检查后 | 调整或保留决定 | 数值 |', '| --- | --- | --- |']
    for entry in history:
        change='；'.join(f"{c['key']} {c['old']} → {c['new']}" for c in entry['changes']) or '逻辑调整或保留配置，见说明'
        lines.append(f"| 第 {entry['after']} 场 | {entry['reason']} | {change} |")
    lines += ['', '## 装备与经济', '', '保留原装备价格、英雄数值、正常收入和每 90 秒补给，不向模拟球员额外发钱。每队每种外场英雄各两名、一名门将，出装路线镜像交换；双方模拟教练均会按比分调整阵型。', '', '| 装备 | 购买次数（含合成材料） |','| --- | ---: |']
    for item,count in zip(final['items'],summary['item_buys']):
        lines.append(f"| {item['name']} | {count} |")
    overlap = summary['pass_kinds'].get('overlap', {})
    lines += ['', '## 验证口径与限制', '',
        '- 实际运行并通过 321 项检查：NPC 新行为 48、赛前设置/补给 53、既有战术 68、经济 38、新角色 41、模式/教程 73。相关日志为 `work/npc-final-*.log`。',
        '- GPU 预览实际执行重炮鞋高速短传、背身转身接球、完整二过一前插接回与常规 11 对 11；`work/npc-preview.log` 无脚本错误，截图已目视检查。',
        '- 使用实际比赛代码与 60 Hz 物理帧，所有 660 名球员的金币、配方消耗、六格库存、E 次数、进球、抢断及控球时间均由汇总脚本核对。每次实际踢球必须对应一条传球或 Q 行为事件。',
        '- 完整对抗采用 22 名 NPC，验证战术频率和系统行为；玩家传球另用真实 Q、8/18/25 米、背身接应、射门装备加成、对手阻挡、补给暂停恢复等场景检查。',
        '- 各组种子、阵型与配置不同，汇总不是一份固定配置的胜率结论，也不是旧 AI 与新 AI 的因果比较。角色踢不同位置，不能用进球数直接宣称职业强弱已均衡。',
        '- 两队侧别胜负不等同于玩家难度。正式关卡的人工试玩手感不由这 30 场全 NPC 比赛替代。', '',
        f"套边在完整比赛中仅 {sum(overlap.values())} 次出球、{overlap.get('complete',0)} 次指定接应成功；独立开放线路的真实物理场景已验证完成。这一战术的实战样本较少，不能据此宣称其成功率稳定。", '',
        '原始数据：`work/balance-npc/match-01.json` 至 `match-30.json`，逐组配置、`adjustments.json`、`summary.json`、`configuration-final.json`。',
        '入口：`simulations/balance_npc.gd --batch=1..15`（拒绝覆盖已完成场次）；`simulations/summarize_npc.py` 只汇总已保存数据，不运行新比赛。', '',
        '设计参考：[EA FC IQ](https://www.ea.com/games/ea-sports-fc/fc-25/news/pitch-notes-fc-25-fc-iq-deep-dive)、[Google Research Football 的 3v1 场景](https://github.com/google-research/football/blob/master/gfootball/scenarios/academy_3_vs_1_with_keeper.py)。实现与数值均为本项目原创。', '']
    (ROOT/'BALANCE_NPC_30.md').write_text('\n'.join(lines),encoding='utf-8')
