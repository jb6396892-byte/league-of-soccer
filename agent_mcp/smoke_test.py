"""Focused integration check: real MCP stdio client -> real Godot -> normal inputs.

Run with --graphics to include a real rendered MCP image. This is not a balance
benchmark or a substitute for an agent's visual judgment.
"""
import argparse
import asyncio
import json
from pathlib import Path
import sys

from mcp import ClientSession, StdioServerParameters
from mcp.client.stdio import stdio_client

ROOT = Path(__file__).resolve().parent.parent


async def main(graphics: bool) -> None:
    checks = 0

    def check(condition, description):
        nonlocal checks
        if not condition:
            raise AssertionError(description)
        checks += 1

    params = StdioServerParameters(command=sys.executable, args=[str(ROOT / "agent_mcp/server.py")])
    async with stdio_client(params) as (read, write):
        async with ClientSession(read, write) as client:
            await client.initialize()

            async def call(name, args=None, error=False):
                result = await client.call_tool("soccer_" + name, args or {})
                check(bool(result.isError) == error, f"{name}: {result.content if result.isError else 'expected error'}")
                if error:
                    return result
                if result.structuredContent:
                    return result.structuredContent
                return json.loads(result.content[0].text)

            tools = await client.list_tools()
            check({"soccer_act", "soccer_screenshot", "soccer_record_review"}.issubset(
                {t.name for t in tools.tools}), "play and review tools advertised")
            guide = await client.read_resource("soccer://guide")
            check("60 Hz" in guide.contents[0].text, "guide available")
            launch = await call("launch", {"headless": not graphics})
            print("SESSION", launch["directory"], flush=True)
            for section in ("heroes", "equipment", "e_skills", "modes", "rogue"):
                await call("catalog", {"section": section})
            await call("start_match", {"mode": "conquest", "level": 15}, error=True)
            await call("start_match", {"mode": "rogue", "ascension": 5}, error=True)

            state = await call("start_match", {"mode": "training", "hero": 2})
            check(state["player"]["human"], "agent retains human controls")
            await asyncio.sleep(0.3)
            observed = await call("observe")
            check(observed["elapsed"] == state["elapsed"] and observed["ball"] == state["ball"], "thinking freezes physics")
            step = await call("act", {"move": [30, 5], "w": "press", "seconds": 0.2})
            check(step["actions"]["w"]["accepted"] and step["state"]["player"]["charging"], "charge begins")
            step = await call("act", {"w": "release", "seconds": 0.2})
            check(step["actions"]["w"]["accepted"] and not step["state"]["player"]["charging"], "charge releases")
            await call("menu", {"action": "refill"})
            await call("act", {"seconds": 1})
            step = await call("act", {"aim": [35, 6], "e": True, "seconds": 0.1})
            check(step["actions"]["e"]["accepted"], "training E casts")
            await call("act", {"seconds": 11}, error=True)
            await call("act", {"move": [999, 0]}, error=True)
            await call("record_review", {"title": "invalid", "summary": "invalid", "limitations": "test",
                "findings": [{"kind": "bug", "severity": "low", "observation": "test", "reproduction": "test", "evidence_ids": ["invented"]}]}, error=True)

            await call("start_match", {"mode": "training", "hero": 5})
            step = await call("act", {"aim": [30, 5], "w": "press", "seconds": 0.25})
            check(len(step["state"]["fields"]) == 1, "live skill fields observable")
            if graphics:
                screenshot = await client.call_tool("soccer_screenshot", {})
                check(not screenshot.isError and any(c.type == "image" for c in screenshot.content), "real MCP image")
                print("SCREENSHOT", screenshot.content[0].text, flush=True)
            else:
                await call("screenshot", error=True)

            state = await call("start_match", {"mode": "free", "seed": 777, "difficulty": "easy", "ally_difficulty": "hard"})
            check(state["ally_difficulty"] == "困难" and state["difficulty"] == "简单", "independent teammate difficulty reaches the real game")
            check(state["phase"] == "shop" and state["player"]["gold"] == 500, "normal match economy")
            purchase = await call("shop", {"action": "buy_item", "id": 0})
            check(purchase["accepted"] and purchase["state"]["player"]["gold"] == 380, "real purchase deduction")
            purchase = await call("shop", {"action": "buy_e", "id": 0})
            check(purchase["accepted"] and purchase["state"]["player"]["gold"] == 290, "real E purchase")
            await call("shop", {"action": "continue"})
            paused = await call("menu", {"action": "timeout"})
            check(paused["accepted"] and paused["state"]["timeout"]["tokens"][0] == 0, "P timeout uses the shared possession-gated token")
            await call("shop", {"action": "continue"})
            view = await call("view", {"annotations": False})
            check(not view["annotations"], "human presentation can be reviewed without MCP annotations")
            view = await call("view", {"annotations": True})
            check(view["annotations"], "MCP annotation patch can be restored")
            step = await call("act", {"e": True, "seconds": 0.5})
            check(step["actions"]["e"]["accepted"] and step["state"]["player"]["e_charges"]["0"] == 0, "charge consumed")
            await call("menu", {"action": "give_ball"}, error=True)
            samples = []
            for _ in range(2):
                state = await call("start_match", {"mode": "free", "seed": 777})
                check(state["ally_difficulty"] == "一般", "omitted teammate difficulty retains normal default")
                await call("shop", {"action": "continue"})
                samples.append((await call("act", {"seconds": 0.5}))["state"])
            check(samples[0]["players"] == samples[1]["players"] and samples[0]["ball"] == samples[1]["ball"], "seeded physics reproduces")

            state = await call("start_match", {"mode": "tutorial"})
            for lesson in range(2):
                state = (await call("act", {"move": state["lesson"]["waypoint"], "seconds": 3}))["state"]
                check(state["lesson"]["index"] == lesson + 1, "tutorial movement advances by real input")
            step = await call("act", {"aim": [50, 0], "q": True, "seconds": 3})
            check(step["actions"]["q"]["accepted"] and step["state"]["lesson"]["index"] == 3, "tutorial real goal")
            step = await call("act", {"w": "press", "seconds": 0.1})
            check(step["state"]["lesson"]["index"] == 3 and step["advanced_seconds"] > 0.09, "tutorial W leaves time to experience the sprint")
            step = await call("act", {"move": step["state"]["lesson"]["waypoint"], "seconds": 3})
            check(step["state"]["phase"] == "shop", "tutorial skill practice leads to shop")
            await call("shop", {"action": "buy_e", "id": 0})
            await call("shop", {"action": "continue"})
            step = await call("act", {"e": True, "seconds": 0.1})
            check(step["state"]["lesson"]["index"] == 4 and step["advanced_seconds"] > 0.09, "tutorial E remains playable after casting")
            step = await call("act", {"move": step["state"]["lesson"]["waypoint"], "seconds": 3})
            check(step["state"]["result_won"] and step["state"]["progress"]["tutorial_done"], "tutorial completed and saved")
            review = await call("record_review", {"title": "MCP integration smoke evidence", "summary": "Scripted inputs completed the real tutorial.",
                "findings": [{"kind": "positive", "severity": "low", "observation": "Tutorial finished through movement, Q, W, purchase and E.",
                              "reproduction": "Follow the five tutorial lessons via MCP.", "evidence_ids": [step["evidence_id"]]}],
                "limitations": "Automated functional test; not a human review or balance estimate. Other modes were not completed in this run."})
            check(Path(review["markdown"]).is_file(), "review saved")
            print("REVIEW", review["markdown"], flush=True)

            state = await call("start_match", {"mode": "rogue", "seed": 23, "ally_difficulty": "easy"})
            check(sum(p["id"].startswith("blue:") for p in state["players"]) == 4, "rogue starts with two outfield teammates and keeper")
            check(not state["player"]["w_unlocked"] and state["difficulty"] == "困难" and state["ally_difficulty"] == "困难", "rogue blank hero/hard AI overrides free teammate choice")
            await call("act", {"q": True}, error=True)
            step = await call("act", {"seconds": 3})
            check(0.8 < step["state"]["elapsed"] < 1.1, "countdown excludes match time")
            events = await call("get_events", {"limit": 2})
            check(len(events["events"]) == 2 and events["next_offset"] == 2, "journal pagination")
            await call("close")
            await call("launch", {"headless": True, "evaluation_access": True})
            state = await call("start_match", {"mode": "conquest", "level": 15})
            check(state["score"] == [0, 1] and state["player"]["gold"] == 500, "content access preserves challenge rules")
            state = await call("start_match", {"mode": "rogue", "ascension": 5})
            check(state["rogue"]["ascension"] == 5, "evaluation access allows locked ascension")
            await call("close")
    print(f"PASS: {checks} integration assertions through MCP stdio", flush=True)


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--graphics", action="store_true")
    asyncio.run(main(parser.parse_args().graphics))
