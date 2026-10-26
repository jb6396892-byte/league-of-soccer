# League of Soccer · Agent MCP

让支持 MCP 的 agent 直接试玩这个 Godot 游戏，并用实际操作、截图和比赛结果写评鉴。采用本地 **stdio MCP + Godot 游戏桥接**，无需 API Key，也不依赖强化学习框架。

## 接入

先将 Godot 4.5.1 Windows 可执行文件放到 `tools/godot/Godot_v4.5.1-stable_win64.exe`，并安装 Python 3.10+。在仓库根目录运行：

```powershell
powershell -ExecutionPolicy Bypass -File .\agent_mcp\setup.ps1
```

脚本创建本地 `.venv`、安装依赖，并生成包含当前克隆路径的 `mcp-config.json` 和 `codex-config.toml`。这些本机配置和虚拟环境不上传 GitHub。在 MCP 客户端中添加生成的 JSON 服务器条目；以下路径仅为示例，使用时以生成文件为准：

```json
{
  "mcpServers": {
    "league-of-soccer": {
      "command": "D:/league of soccar/agent_mcp/.venv/Scripts/python.exe",
      "args": ["D:/league of soccar/agent_mcp/server.py"]
    }
  }
}
```

这是标准本地 MCP 服务器，不是网页服务。客户端负责启动进程并连接 stdin/stdout；直接双击脚本不会打开控制台菜单。修改客户端配置后重连，工具统一以 `soccer_` 开头。本任务不修改你的全局客户端配置。

Codex 可在终端执行下面的接入命令（替换为实际路径），或把生成的 `codex-config.toml` 条目加入自己的配置。格式已核对本机 CLI 和 [官方 MCP 文档](https://learn.chatgpt.com/docs/extend/mcp?surface=cli)：

```powershell
codex mcp add league-of-soccer -- "D:/league of soccar/agent_mcp/.venv/Scripts/python.exe" "D:/league of soccar/agent_mcp/server.py"
```

更换电脑或移动源码后重新运行 `setup.ps1`，即可按新路径生成配置。普通玩家的纯游戏 ZIP 不包含此开发工具。

## 给 agent 的指令示例

准备让新对话试玩时，先按本页接入，再读取 `soccer://guide`。原开发机另有 `work/agent-playtest-handoff.md` 和历次操作证据；这些本地记录不包含在公开仓库中。

> 使用 league-of-soccer MCP 试玩游戏。先读取 soccer://guide，以图形模式启动，完成新手教程，再选择一个征服关卡或一层肉鸽。自己观察局势并操作，查看截图，记录操作手感、NPC 接应和足球辨识度。评鉴必须引用实际证据编号，明确未测试内容，最后保存报告并关闭游戏。

客户端也可调用内置 `soccer_review` prompt。初次流程：

1. `soccer_launch(headless=false)`：启动独立游戏窗口。
2. 读取 `soccer://guide`，调用 `soccer_catalog(section="heroes")` 等查询真实规则。
3. `soccer_start_match(mode="tutorial")`，按返回的目标操作。
4. `soccer_act(move=[17,6], seconds=1)`：移动并推进 1 秒。观察后再下一个动作。
5. 正式比赛开局先用 `soccer_shop` 购买，再 `action="continue"`。
6. `soccer_screenshot()` 返回真实画面和证据编号；`soccer_record_review` 保存评鉴。
7. `soccer_close()` 关闭此次游戏。客户端正常断开也会清理自己的子进程。

## 操作约定

- 自由模式可独立设置 `soccer_start_match(difficulty="hard", ally_difficulty="normal")`：前者控制对手，后者控制队友，均支持 `easy/normal/hard`，默认一般。观察结果的 `ally_difficulty` 返回实际队友难度；征服、肉鸽、训练和教程仍使用各自固定规则。
- **分步推进**：只有 `soccer_act` 推进物理，固定 60 Hz，每次 1/60–10 秒；思考、观察、购物和截图不消耗比赛时间。遇进球、商店、教学步骤或结算会提前停住。
- 教程 W/E 需释放技能、体验至少 2 秒并移动到 `lesson.waypoint` 的目标圈；仅按技能键不会跳到下一步。
- 自由/征服保留赛前商店，进球不再自动购物。每队共享暂停次数：开局 1 次，每 90 秒有效比赛时间补 1 次，上限 2 次。己方持球时用 `soccer_menu(action="timeout")`，双方可购买/换阵，15 秒后或 `continue` 提前结束，申请方中线开球。NPC 也会申请；`timeout` 状态包含次数和不可用原因。
- **MCP 特别补丁**：默认加载 `annotation_hud.gd`，显示全员状态和领域说明。用 `soccer_view(annotations=false)` 查看普通玩家的简洁界面；`true` 恢复详细标注。补丁仅在 agent 会话加载，不进入普通发行包。声音在 agent 会话中关闭。
- 位置为世界坐标 `[x,z]`，单位米。蓝队向右侧 `[50,0]` 球门进攻。不是屏幕像素。
- `aim` 等价于左键转向并停步；`move` 等价于右键，目标会持续。两者同次提交先转向再设置移动。球员随后仍按原游戏移动规则转向。
- Q/W/E 每次调用只触发一次。月影 W 先 `w="press"` 蓄力，再另一次 `w="release"`；镇域 W 的领域位置用 `aim` 指定。动作受范围、冷却和控制效果限制，查看返回的 `accepted`。
- 装备、E、阵型、天赋与卖出槽位用 **0 起始 ID**；征服关卡用 **1–15**。
- `headless=true` 可快速读取状态、操作，但不能截图。视觉评鉴必须使用真实截图。

## 工具

| 工具 | 用途 |
|---|---|
| `soccer_launch` / `soccer_close` | 启动和结束独立会话 |
| `soccer_catalog` | 角色、装备、E、关卡、肉鸽规则 |
| `soccer_start_match` | 自由、征服、教程、训练、肉鸽 |
| `soccer_observe` | 球与球员位置、状态、球权、经济、当前商店/奖励 |
| `soccer_act` | 移动、瞄准、Q/W/E、等待和分步推进 |
| `soccer_shop` | 购买、出售、E 装备、阵型和继续 |
| `soccer_menu` | 战术暂停、天赋、存档回退、主界面、开发人员、训练辅助 |
| `soccer_view` | 跟随/全景镜头、帮助、商店页签、MCP 详细标注开关 |
| `soccer_screenshot` | 实际渲染图片，MCP image 内容 |
| `soccer_get_events` | 分页读取此次操作与证据 |
| `soccer_record_review` | 保存引用证据的 Markdown + JSON 评鉴 |

默认保持正常解锁规则。要检查后期内容，在启动时设置 `evaluation_access=true`，只在独立会话中解锁全部征服关卡及肉鸽进阶，不增加场内属性。这项权限写入证据；不代表实际通关。

自由模式使用指定随机种子；肉鸽使用远征种子；征服沿用每关固定种子。相同版本、种子和操作序列可复现。控制的球员始终保留玩家行为，其余 NPC 正常运行。工具不读取 NPC 的未来决策、未来天赋或 RNG 内部状态。

## 评鉴与存档

每次 `soccer_launch` 创建 `work/agent-sessions/<时间-编号>/`，包含 `events.jsonl`、游戏日志、截图、评鉴和独立进度。不会读取或覆盖玩家的 `user://` 存档。会话内可使用肉鸽存档回退；关闭后文件保留，但下次 launch 默认开始新的独立会话。

报告中的比赛清单由实际引擎结算状态汇总。发现需注明复现步骤、证据编号和类型：bug、平衡、易用性、视觉或优点。工具只检查证据是否存在，不替 agent 证明结论，也不会自动编造评分。视觉发现必须引用截图。少量试玩不能推导人类通关率。

游戏桥仅连接本机随机端口并校验每次启动的随机令牌，MCP 对外仍是 stdio。没有公网监听、在线对战控制、任意脚本执行、改比分或正式比赛作弊接口。只能关闭自己启动的游戏进程。

## 开源来源

- [官方 Python MCP SDK v1.30.0](https://github.com/modelcontextprotocol/python-sdk/tree/v1.30.0)：实际使用，MIT；锁定仍受支持的 v1 FastMCP API，升级 v2 需相应迁移。
- [Godot RL Agents 的同步实现](https://github.com/edbeeching/godot_rl_agents_plugin/blob/998c357a0cd09b37f40a36d70c7867fc9f682338/addons/godot_rl_agents/sync.gd)：参考其观察、动作、固定步长和等待控制方式，没有引入训练依赖或复制源码。
- [Coding-Solo/godot-mcp](https://github.com/Coding-Solo/godot-mcp)：调研其启动/调试/场景工具；它主要服务开发编辑，本工具补充足球比赛专用操作。

## 开发验证

`agent_mcp/.venv/Scripts/python.exe agent_mcp/smoke_test.py --graphics` 通过官方 MCP 客户端连接真实 Godot，检查冻结、合法输入、购物、教程完成、技能、进度隔离、截图和报告。无需重跑整套平衡赛。[evaluation.xml](evaluation.xml) 是基于 2026-10-23 游戏目录的 10 道只读 agent 查询题，答案已从真实 MCP 返回值核对；更新装备或技能后需相应维护答案。

原开发阶段另实际操作完成征服首关和肉鸽第一层，并检查三选一天赋、第 2 层换边开球及新技能生效。该次评鉴与截图保存在原开发机的 `work/agent-sessions/`，不随公开源码发布；新会话应产生自己的证据。
