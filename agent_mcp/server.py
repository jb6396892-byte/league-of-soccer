"""Local stdio MCP for playing and reviewing League of Soccer through Godot."""
from __future__ import annotations

import asyncio
from contextlib import asynccontextmanager
from datetime import datetime, timezone
import json
import os
from pathlib import Path
import secrets
import subprocess
from typing import Annotated, Any, Literal
from uuid import uuid4

from mcp.server.fastmcp import FastMCP, Image
from mcp.server.fastmcp.exceptions import ToolError
from pydantic import BaseModel, ConfigDict, Field

ROOT = Path(__file__).resolve().parent.parent
GODOT = ROOT / "tools/godot/Godot_v4.5.1-stable_win64.exe"
BRIDGE = ROOT / "agent_mcp/bridge.gd"
Point = tuple[Annotated[float, Field(ge=-55, le=55, allow_inf_nan=False)],
              Annotated[float, Field(ge=-35, le=35, allow_inf_nan=False)]]
READ = {"readOnlyHint": True, "destructiveHint": False, "idempotentHint": True, "openWorldHint": False}
WRITE = {"readOnlyHint": False, "destructiveHint": False, "idempotentHint": False, "openWorldHint": False}

GUIDE = """# League of Soccer agent controls
Use soccer_launch, then soccer_catalog and soccer_start_match. The game waits for
you between calls: thinking, observation, and screenshots never advance physics.
Only soccer_act advances time, at 60 Hz, for 1/60 to 10 seconds. It stops early
at goals, shops, tutorial lessons, and results. Kickoff countdown uses simulated
time but does not consume match time. Use an act with only seconds to wait.

World positions are [x,z] in metres. Blue (you) attacks +x, goal line at x=48;
red attacks -x. Pitch is x=-48..48, z=-30..30; goal posts are z=+/-5.2.
Aiming at [50,0] shoots through the goal centre. All catalog IDs and reward/slot
indices are ZERO based; conquest levels are ONE based. Observe stable player IDs
such as blue:10. No AI hidden intentions or future random rolls are exposed.

Aim acts like left click: turns and stops the player; move is like right click
and persists until another movement/aim command. If both supplied, aim executes
first, then move. Movement will turn the player as in the real game. Q/W/E fire
once at the beginning of a step, never repeatedly. Aim+Q is useful for passes and
shots. W='press' begins 月影's charge; a later W='release' dashes. 镇域 W and 月影 E
use aim as their target. Check actions.accepted; a failed attempt still advances
the requested time. Shop/menu errors do not secretly advance time.

Choose a hero, difficulty (opponents), ally_difficulty (teammates) and duration
for free matches; the two difficulty choices are independent. Conquest overrides
fixed hero/difficulty/seed/duration. Rogue starts with a blank hero, 2 outfield
teammates and a keeper; select line 1=back/2=mid/3=front. Both teams use hard AI.
The player is always agent controlled, never replaced by an autoplay policy.
The normal unlock progression is preserved unless evaluation_access=true was
explicitly selected at launch. That option opens content, not extra match stats.

Shop: inspect current price and blocked reason, buy/equip, then 'continue'.
Free/conquest have a prematch shop; goals do not open shops. Each team starts
with 1 shared timeout, gains 1 every 90 active seconds, capped at 2. With your
team in possession, soccer_menu(action='timeout') spends one for a 15-second
shop and formation break. Either team can buy; the caller takes centre kickoff
afterwards. NPCs can also call timeouts. Read observation.timeout for stock and
blocked reason. 'continue' ends the break early.
MCP adds detailed player/field annotations by default. Use
soccer_view(annotations=false) before judging the ordinary human UI, and true
for the agent overlay. Audio is disabled in agent sessions.
Rogue: choose offered talent index through soccer_menu; checkpoint rewards can
require two choices. Checkpoint resume stays inside this isolated session.
Training aids work only in training; tutorial has only its original shop.
soccer_start_match/home abandons the current match, and new rogue runs clear the
session checkpoint. Ordinary player's progress is never read or overwritten.

Review workflow: play tutorial or training to learn controls, then at least one
complete real match. Take graphical screenshots before judging visual quality.
Use soccer_record_review with evidence IDs from actual returned observations,
actions or screenshots. Mark subjective opinions as opinions, bugs with repro
steps, and untested modes as untested. Scripted trials are not human win rates.
Session files record tool requests, snapshots, screenshots and reviews under
work/agent-sessions. The journal is bounded per read using soccer_get_events.
No online matches, arbitrary code execution, arbitrary save editing or forced
wins are exposed. This server controls only the Godot process it launches.
"""


class Runtime:
    def __init__(self) -> None:
        self.process: asyncio.subprocess.Process | None = None
        self.writer: asyncio.StreamWriter | None = None
        self.reader: asyncio.StreamReader | None = None
        self.directory: Path | None = None
        self.lock = asyncio.Lock()
        self.serial = 0
        self.records: list[dict] = []
        self.headless = False

    def record(self, kind: str, request: dict, result: dict) -> dict:
        if self.directory is None:
            raise ToolError("Launch a session first.")
        evidence_id = f"e{len(self.records) + 1:05d}"
        result = {**result, "evidence_id": evidence_id}
        entry = {"id": evidence_id, "timestamp": datetime.now(timezone.utc).isoformat(),
                 "kind": kind, "request": request, "result": result}
        with (self.directory / "events.jsonl").open("a", encoding="utf-8") as out:
            out.write(json.dumps(entry, ensure_ascii=False, allow_nan=False) + "\n")
        self.records.append(entry)
        return result

    async def launch(self, headless: bool, evaluation_access: bool) -> dict:
        async with self.lock:
            return await self._launch(headless, evaluation_access)

    async def _launch(self, headless: bool, evaluation_access: bool) -> dict:
        if self.process is not None:
            raise ToolError("Session already launched. Use soccer_close before launching another.")
        if not GODOT.is_file():
            raise ToolError(f"Godot executable missing: {GODOT}")
        self.directory = ROOT / "work/agent-sessions" / (
            datetime.now().strftime("%Y%m%d-%H%M%S-") + uuid4().hex[:8])
        self.directory.mkdir(parents=True)
        self.records = []
        self.serial = 0
        self.headless = headless
        token = secrets.token_urlsafe(32)
        accepted = asyncio.get_running_loop().create_future()

        async def connected(reader: asyncio.StreamReader, writer: asyncio.StreamWriter) -> None:
            try:
                hello = json.loads(await asyncio.wait_for(reader.readline(), 5))
                valid = (isinstance(hello, dict) and hello.get("hello") == "soccer-agent-v1"
                         and secrets.compare_digest(str(hello.get("token", "")), token))
                if valid and not accepted.done():
                    accepted.set_result((reader, writer))
                    return
            except (ValueError, TimeoutError, OSError):
                pass  # Unauthenticated local connections never reach the game.
            writer.close()
            await writer.wait_closed()

        listener = await asyncio.start_server(connected, "127.0.0.1", 0, limit=2**20)
        port = listener.sockets[0].getsockname()[1]
        args = [str(GODOT), "--path", str(ROOT), "--script", str(BRIDGE),
                "--log-file", str(self.directory / "game.log"), "--audio-driver", "Dummy",
                "--resolution", "1280x800"]
        if headless:
            args += ["--headless"]
        args += ["--", f"--port={port}", f"--session-dir={self.directory.as_posix()}",
                 f"--evaluation-access={str(evaluation_access).lower()}"]
        env = {**os.environ, "SOCCER_AGENT_TOKEN": token}
        try:
            with (self.directory / "process.log").open("wb") as log:
                self.process = await asyncio.create_subprocess_exec(
                    *args, cwd=ROOT, env=env, stdout=log, stderr=log,
                    creationflags=subprocess.CREATE_NO_WINDOW if os.name == "nt" else 0)
            exited = asyncio.create_task(self.process.wait())
            done, _ = await asyncio.wait([accepted, exited], timeout=45,
                                         return_when=asyncio.FIRST_COMPLETED)
            if accepted not in done:
                await self._close()
                raise ToolError(f"Godot failed to connect. Inspect {self.directory / 'process.log'}")
            self.reader, self.writer = accepted.result()
            exited.cancel()
        finally:
            # Stop accepting peers. wait_closed() would also wait for our live
            # game connection on Python 3.12+, deadlocking the launch response.
            listener.close()
        state = await self._request("observe", {"detailed": False}, record=False)
        return self.record("launch", {"headless": headless, "evaluation_access": evaluation_access},
                           {"session_id": self.directory.name, "directory": str(self.directory), "godot_pid": self.process.pid,
                            "state": state, "controls": "Read soccer://guide; start with soccer_catalog and soccer_start_match."})

    async def call(self, method: str, params: dict, *, record: bool = True) -> dict:
        async with self.lock:
            return await self._request(method, params, record=record)

    async def _request(self, method: str, params: dict, *, record: bool = True) -> dict:
        if self.writer is None or self.reader is None or self.process is None or self.process.returncode is not None:
            raise ToolError("No connected game. Use soccer_launch. Previous session files remain on disk.")
        self.serial += 1
        payload = {"id": self.serial, "method": method, "params": params}
        try:
            self.writer.write((json.dumps(payload, allow_nan=False) + "\n").encode())
            await self.writer.drain()
            line = await asyncio.wait_for(self.reader.readline(), 30)
            if not line:
                raise ConnectionError("Godot closed the bridge.")
            reply = json.loads(line)
        except (OSError, TimeoutError, ValueError) as error:
            await self._close()
            raise ToolError(f"Game connection lost; action outcome is unknown, not retried. Check {self.directory / 'process.log'}: {error}") from error
        if reply.get("id") != self.serial:
            await self._close()
            raise ToolError("Bridge response ID mismatch; session closed to prevent replaying an action.")
        result = reply["result"]
        if record:
            result = self.record(method, params, result)
        if "error" in result:
            raise ToolError(result["error"])
        return result

    async def close(self) -> dict:
        async with self.lock:
            return await self._close()

    async def _close(self) -> dict:
        if self.writer is not None:
            self.writer.close()
            await self.writer.wait_closed()
            self.writer = None
            self.reader = None
        if self.process is not None:
            try:
                await asyncio.wait_for(self.process.wait(), 4)
            except TimeoutError:
                self.process.terminate()
                await self.process.wait()
            self.process = None
        return {"closed": True, "directory": str(self.directory) if self.directory else None,
                "recorded_events": len(self.records)}


runtime = Runtime()


@asynccontextmanager
async def lifespan(_server: FastMCP):
    try:
        yield runtime
    finally:
        await runtime.close()


mcp = FastMCP("league-of-soccer", lifespan=lifespan, log_level="WARNING",
              instructions="Play the real Godot football game in fixed steps. Read soccer://guide. "
                           "Use screenshots for visual judgments and evidence IDs for reviews.")


@mcp.resource("soccer://guide")
def soccer_guide() -> str:
    """Control semantics, modes, coordinates, evidence and honest review workflow."""
    return GUIDE


@mcp.prompt()
def soccer_review(focus: str = "controls, AI tactics, balance and visual clarity") -> str:
    """Play a real session, then write a reproducible evidence-backed review."""
    return (f"Review League of Soccer focusing on {focus}. Read soccer://guide. "
            "Launch with headless=false; learn controls through tutorial/training; "
            "complete at least one match with your own actions. Observe and take screenshots. "
            "Record facts, opinions and bugs separately with real evidence IDs/repro steps. "
            "Do not claim unplayed modes or human win rates. Save with soccer_record_review.")


@mcp.tool(annotations=WRITE)
async def soccer_launch(headless: bool = False, evaluation_access: bool = False) -> dict[str, Any]:
    """Launch an isolated game, frozen between actions. headless disables screenshots.

    evaluation_access pre-unlocks conquest/ascensions ONLY in this test session;
    it is recorded in evidence. Default uses normal progression. One game/server.
    """
    return await runtime.launch(headless, evaluation_access)


@mcp.tool(annotations=READ)
async def soccer_observe(detailed: bool = False) -> dict[str, Any]:
    """Read frozen positions, ball, player stats, phase, shop, rewards and objectives.

    detailed includes every NPC's equipment/stats and purchases. IDs are stable
    within a match. No clock advancement or AI hidden intentions are exposed.
    """
    return await runtime.call("observe", {"detailed": detailed})


@mcp.tool(annotations=READ)
async def soccer_catalog(section: Literal["heroes", "equipment", "e_skills", "modes", "rogue"]) -> dict[str, Any]:
    """Read actual game definitions, IDs, prices, recipes, skills and mode rules.

    Requires launch. IDs are zero based; conquest level arguments are one based.
    """
    return await runtime.call("catalog", {"section": section})


@mcp.tool(annotations=WRITE)
async def soccer_start_match(
    mode: Literal["free", "conquest", "tutorial", "training", "rogue"],
    hero: Annotated[int, Field(ge=0, le=5)] = 0,
    minutes: Annotated[int, Field(ge=5, le=15)] = 5,
    difficulty: Literal["easy", "normal", "hard"] = "normal",
    ally_difficulty: Literal["easy", "normal", "hard"] = "normal",
    level: Annotated[int, Field(ge=1, le=15)] = 1,
    line: Literal[1, 2, 3] = 3,
    ascension: Annotated[int, Field(ge=0, le=5)] = 0,
    seed: Annotated[int, Field(ge=1, le=2147483647)] = 20261023,
    formation: Annotated[int, Field(ge=0, le=4)] = 0,
) -> dict[str, Any]:
    """Start a new match, abandoning the current one. Check current evidence first.

    Free uses hero/minutes/difficulty/ally_difficulty/formation; difficulty controls
    opponents and ally_difficulty controls teammates. Conquest uses level (1-15) and
    its fixed rules/seed, overriding hero when prescribed. Rogue uses line
    (1 back, 2 mid, 3 front), ascension and seed; starts blank with hard AI.
    Training/tutorial use original practice rules. Normal unlocks apply.
    """
    return await runtime.call("start", {"mode": mode, "hero": hero, "minutes": minutes,
        "difficulty": ["easy", "normal", "hard"].index(difficulty), "level": level,
        "ally_difficulty": ["easy", "normal", "hard"].index(ally_difficulty),
        "line": line, "ascension": ascension, "seed": seed, "formation": formation})


@mcp.tool(annotations=WRITE)
async def soccer_act(
    seconds: Annotated[float, Field(ge=1/60, le=10, allow_inf_nan=False)] = 0.25,
    move: Point | None = None,
    aim: Point | None = None,
    q: bool = False,
    w: Literal["none", "press", "release"] = "none",
    e: bool = False,
) -> dict[str, Any]:
    """Issue one input then advance 1/60–10 simulated seconds, stopping at decisions.

    move/aim are world [x,z]. Blue attacks [50,0]. Aim stops and turns, then
    optional move sets a persistent destination. Q/W/E fire once at step start;
    月影 W needs press, charge time, release. 镇域 W needs aim. Use no inputs to
    wait/count down. Check returned actions.accepted; failed attempts cost time.
    Shops/results require soccer_shop/soccer_menu instead.
    """
    return await runtime.call("act", {"seconds": seconds, "move": move, "aim": aim,
                                       "q": q, "w": w, "e": e})


@mcp.tool(annotations=WRITE)
async def soccer_shop(
    action: Literal["buy_item", "sell_item", "buy_e", "equip_e", "formation", "continue"],
    id: Annotated[int, Field(ge=0, le=21)] = 0,
) -> dict[str, Any]:
    """Shop using real gold/recipes/charges; continue closes shop and lets NPCs buy.

    id is zero-based equipment/E/formation ID, or inventory SLOT for sell_item.
    Ignored for continue. Read state.shop for current price and blocked reason.
    """
    return await runtime.call("shop", {"action": action, "id": id})


@mcp.tool(annotations=WRITE)
async def soccer_menu(
    action: Literal["home", "credits", "talent", "resume_checkpoint", "practice_shop", "timeout",
                    "give_ball", "reset_field", "refill", "serve_shot"],
    index: Annotated[int, Field(ge=0, le=2)] = 0,
) -> dict[str, Any]:
    """Choose a rogue reward (zero-based index), resume checkpoint, or navigate.

    home/credits abandon the match. Practice aids only work in training;
    practice_shop is also allowed in tutorial. serve_shot requires keeper.
    Reward choices may open a second checkpoint reward before the next match.
    timeout uses one team token (P); only when your team possesses the ball.
    Both teams can shop, then the requesting team takes the centre kickoff.
    """
    return await runtime.call("menu", {"action": action, "index": index})


@mcp.tool(annotations=WRITE)
async def soccer_view(camera: Literal["follow", "overview"] = "follow", help: bool = False,
                      shop_tab: Literal[0, 1, 2] = 0, annotations: bool = True) -> dict[str, Any]:
    """Set presentation without advancing physics. shop_tab: 0 parts,1 items,2 E.

    Use overview for tactical screenshots, follow for ball/skill clarity,
    help=true for controls and full rogue build. Requires an active match.
    annotations=false renders the ordinary human UI; true adds the MCP-only
    player numbers, combined status badges and field labels. Rules are identical.
    """
    return await runtime.call("view", {"camera": camera, "help": help, "shop_tab": shop_tab, "annotations": annotations})


@mcp.tool(annotations=READ)
async def soccer_screenshot() -> list:
    """Capture the actual rendered game as an MCP image plus evidence ID/path.

    No physics advancement. Requires headless=false; never synthesizes an image.
    """
    filename = f"screen-{uuid4().hex[:12]}.png"
    result = await runtime.call("screenshot", {"filename": filename})
    metadata = {key: result[key] for key in ("path", "evidence_id")}
    return [json.dumps(metadata), Image(path=result["path"])]


@mcp.tool(annotations=READ)
async def soccer_get_events(offset: Annotated[int, Field(ge=0)] = 0,
                             limit: Annotated[int, Field(ge=1, le=50)] = 10,
                             include_state: bool = False) -> dict[str, Any]:
    """Page the current session journal; works after close. include_state adds snapshots.

    offset is zero based. Returned evidence IDs can support a review. All full
    records are also saved as events.jsonl in the session directory.
    """
    records = runtime.records[offset:offset + limit]
    if not include_state:
        records = [{"id": r["id"], "kind": r["kind"], "request": r["request"],
                    "timestamp": r["timestamp"], "error": r["result"].get("error")}
                   for r in records]
    return {"total": len(runtime.records), "events": records,
            "next_offset": offset + len(records) if offset + len(records) < len(runtime.records) else None}


class Finding(BaseModel):
    model_config = ConfigDict(extra="forbid")
    kind: Literal["bug", "balance", "usability", "visual", "positive"]
    severity: Literal["low", "medium", "high"]
    observation: Annotated[str, Field(min_length=1, max_length=2000)]
    reproduction: Annotated[str, Field(min_length=1, max_length=2000)]
    evidence_ids: Annotated[list[str], Field(min_length=1, max_length=20)]


@mcp.tool(annotations=WRITE)
async def soccer_record_review(
    title: Annotated[str, Field(min_length=1, max_length=200)],
    summary: Annotated[str, Field(min_length=1, max_length=6000)],
    findings: Annotated[list[Finding], Field(min_length=1, max_length=30)],
    limitations: Annotated[str, Field(min_length=1, max_length=3000)],
) -> dict[str, Any]:
    """Save a Markdown+JSON review tied to real evidence from this session.

    Findings separate bugs/balance/usability/visual/positive observations.
    Provide reproducible steps, evidence IDs, and honest untested limitations.
    Visual findings must cite an actual screenshot. Referencing evidence does
    not prove a claim; the reviewer must inspect it. No automatic quality score.
    """
    known = {record["id"]: record for record in runtime.records}
    for finding in findings:
        if any(eid not in known for eid in finding.evidence_ids):
            raise ToolError("Unknown evidence ID; use IDs returned by this session's tools.")
        if finding.kind == "visual" and not any(
            known[eid]["kind"] == "screenshot" and "path" in known[eid]["result"]
            for eid in finding.evidence_ids
        ):
            raise ToolError("Visual findings require a real screenshot evidence ID.")
    if runtime.directory is None:
        raise ToolError("Launch and play a session before recording a review.")
    # Derive completed matches from actual engine results, de-duplicated per match.
    completed = {}
    for record in runtime.records:
        state = record["result"].get("state", record["result"])
        if state.get("phase") == "result":
            completed[state["match_id"]] = {key: state[key] for key in
                ("match_id", "mode", "seed", "score", "elapsed", "result_won", "evaluation_access")}
    review = {"title": title, "summary": summary, "limitations": limitations,
              "findings": [f.model_dump() for f in findings], "completed_matches": list(completed.values())}
    base = runtime.directory / f"review-{uuid4().hex[:10]}"
    base.with_suffix(".json").write_text(json.dumps(review, ensure_ascii=False, indent=2), encoding="utf-8")
    lines = [f"# {title}", "", summary, "", "## 实际完成的比赛", "",
             "```json", json.dumps(review["completed_matches"], ensure_ascii=False, indent=2), "```", ""]
    for f in findings:
        lines += [f"## {f.kind} / {f.severity}", "", f.observation, "",
                  f"复现：{f.reproduction}", "", f"证据：{', '.join(f.evidence_ids)}", ""]
    lines += ["## 范围与限制", "", limitations, ""]
    base.with_suffix(".md").write_text("\n".join(lines), encoding="utf-8")
    return runtime.record("review", {"title": title}, {"markdown": str(base.with_suffix('.md')),
                           "json": str(base.with_suffix('.json')), "completed_matches": len(completed)})


@mcp.tool(annotations=WRITE)
async def soccer_close() -> dict[str, Any]:
    """Close only this server's game; preserve session evidence, screenshots and saves."""
    return await runtime.close()


if __name__ == "__main__":
    mcp.run(transport="stdio")
