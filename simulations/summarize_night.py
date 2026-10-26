"""Summarize current night-campaign data; no simulations or balance edits."""
import collections
import json
import pathlib
import statistics
import sys

revision = sys.argv[1] if len(sys.argv) > 1 else "baseline"
root = pathlib.Path(__file__).resolve().parents[1]
base = root / "work" / "balance-night" / revision
summary = {"revision": revision}

def load(folder):
    return [json.loads(p.read_text(encoding="utf-8")) for p in sorted(folder.glob("*.json")) if p.stem.isdecimal()]

for suite in ["free", "pvp", "coop", "long"]:
    games = load(base / suite)
    if not games:
        continue
    groups = collections.defaultdict(list)
    purchases = collections.Counter()
    unused_charges = collections.Counter()
    keepers = []
    humans = collections.defaultdict(lambda: collections.Counter())
    for game in games:
        groups[game["difficulty"]].append(game)
        purchases.update(event["item"] for event in game["purchases"])
        keepers.extend(game["keepers"])
        for player in game["players"]:
            unused_charges.update({int(k): v for k, v in player["e_charges"].items()})
            if player["human"]:
                row = humans[player["hero"]]
                row["appearances"] += 1
                row.update({k: player["stats"][k] for k in ["goals", "tackles", "turnovers", "casts", "e_casts"]})
    result = {"matches": len(games), "simulated_minutes": round(sum(g["seconds"] for g in games) / 60, 1),
              "capped": sum(not g["finished"] for g in games), "items_purchased": dict(sorted(purchases.items())),
              "human_roles": dict(sorted(humans.items())), "difficulty": {},
              "keeper_holds": len(keepers), "keeper_lost": sum(e["result"] == "lost" for e in keepers),
              "unused_e_charges": dict(unused_charges)}
    for difficulty, rows in sorted(groups.items()):
        margins = [g["score"][g["controlled_team"]] - g["score"][1-g["controlled_team"]] for g in rows]
        result["difficulty"][difficulty] = {"games": len(rows), "wins": sum(m > 0 for m in margins),
            "mean_margin": round(statistics.mean(margins), 2), "scores": [g["score"] for g in rows],
            "max_speed": round(max(g["max_speed"] for g in rows), 2)}
    summary[suite] = result
    print(suite, result["matches"], "matches", result["simulated_minutes"], "minutes", "capped", result["capped"])
    print(" difficulty", result["difficulty"])
    print(" gear", result["items_purchased"], "keeper lost", result["keeper_lost"], "/", result["keeper_holds"])
    print(" humans", result["human_roles"])

conquest = []
for path in sorted((root / "work" / "conquest-balance" / ("night-" + revision)).glob("*.json")):
    conquest.append(json.loads(path.read_text(encoding="utf-8")))
if conquest:
    levels = collections.defaultdict(list)
    for game in conquest:
        levels[game["level"]].append(game)
    summary["conquest"] = {level: {"trials": len(rows), "wins": sum(g["won"] for g in rows),
        "scores": [g["score"] for g in rows], "mean_seconds": round(statistics.mean(g["seconds"] for g in rows), 1)}
        for level, rows in sorted(levels.items())}
    print("conquest", summary["conquest"])

runs = load(base / "rogue")
if runs:
    summary["rogue"] = [{"round": r["round"], "seed": r["seed"], "line": r["line"], "outcome": r["outcome"],
        "matches": len(r["matches"]), "deepest": max(m["stage"] for m in r["matches"]), "retries": r["retries"],
        "seconds": round(sum(m["seconds"] for m in r["matches"])),
        "early_goals": [sum(m["score"][team] for m in r["matches"] if m["stage"] <= 5) for team in [0, 1]],
        "late_goals": [sum(m["score"][team] for m in r["matches"] if m["stage"] >= 11) for team in [0, 1]]} for r in runs]
    print("rogue", summary["rogue"])
base.mkdir(parents=True, exist_ok=True)
(base / "summary.json").write_text(json.dumps(summary, ensure_ascii=False, indent=2), encoding="utf-8")
