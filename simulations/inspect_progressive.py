"""Inspect saved pairs without running matches."""
import json
import statistics
import sys
from collections import Counter
from pathlib import Path

root = Path(__file__).resolve().parents[1] / "work" / "balance-progressive"
batch = int(sys.argv[1])
config = json.loads((root / f"configuration-{batch:02}.json").read_text(encoding="utf-8"))
games = [json.loads((root / f"match-{i:02}.json").read_text(encoding="utf-8")) for i in (batch*2-1, batch*2)]
all_games = [json.loads(p.read_text(encoding="utf-8")) for p in root.glob("match-*.json")]
buys = Counter(p["item"] for g in games for p in g["purchases"])
all_buys = Counter(p["item"] for g in all_games for p in g["purchases"])
first = []
final_counts = Counter()
for g in games:
    for row in g["players"]:
        personal = [p for p in g["purchases"] if p["team"] == row["team"] and p["shirt_number"] == row["shirt_number"] and config["items"][p["item"]]["tier"] == 1]
        if personal:
            first.append(personal[0]["time"])
        final_counts[sum(config["items"][i]["tier"] == 1 for i in row["inventory"])] += 1
print("PAIR", batch, [(g["round"],g["score"],g["seconds"]) for g in games])
print("ROLES name/goals/tackles/held/saves/W/E")
for kind, name in enumerate(config["hero_names"]):
    totals = Counter()
    for g in games:
        for row in g["players"]:
            if row["role"] == kind:
                totals.update(row["stats"])
    print(name, [round(totals[k],1) for k in ("goals","tackles","possession_seconds","saves","casts","e_casts")])
print("ITEM BUYS", dict(sorted(buys.items())))
print("NEVER BOUGHT", [f"{i}:{item['name']}" for i,item in enumerate(config["items"]) if all_buys[i] == 0])
print("FINALS AT END", dict(sorted(final_counts.items())), "FIRST MEDIAN", round(statistics.median(first),1) if first else None)
print("E BUYS", dict(Counter(p["skill"] for g in games for p in g["e_purchases"])), "E CASTS", dict(Counter(p["skill"] for g in games for p in g["e_casts"])))
