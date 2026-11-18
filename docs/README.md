# Defold Game Framework — 文档总入口（路由表）

> 本文件只做**路由**，不写正文。文档分两层，别混：

| 层 | 位置 | 随依赖分发？ | 谁看 |
|---|---|---|---|
| **框架通用层** | `framework/docs/` | ✅ 随（在 `framework/` 内，每个游戏仓库都能查到） | 所有游戏的 agent / 维护者 |
| **仓库层** | `docs/`（本目录） | ❌ 不随（瘦 ZIP 只打 `framework/`） | 只给框架仓库维护者看 |

判据：**新项目里要能查到的东西，必须写进 `framework/docs/`**。写在本目录的内容，
走整仓 ZIP 时虽然也在依赖里，但不在 `[library] include_dirs` 里，游戏侧不会把它当资料索引去查。

## 我要做什么 → 去哪

| 需求 | 去处 |
|---|---|
| 新项目初始化 / 从现有项目复制启动 | [`framework/docs/project-bootstrap.md`](../framework/docs/project-bootstrap.md) |
| 遇到难解决的问题（三步排障法第 1 步） | [`framework/docs/README.md`](../framework/docs/README.md)（踩坑记录索引） |
| 旧流程：以 miner 为模板批量建游戏 | [`docs/creating-games.md`](creating-games.md) |
| 工程架构 / V1 范围 | [`architecture/architecture.md`](architecture/architecture.md) |
| 模块 API 合约 | [`architecture/api-contracts.md`](architecture/api-contracts.md) |
| 两层 UI 与品类复用 | [`architecture/two-layer-ui.md`](architecture/two-layer-ui.md) |
| 依赖锁定（URL + SHA256 + bob 校验） | [`planning/dependencies.json`](planning/dependencies.json) |
| 任务顺序与验收 | [`planning/implementation-plan.md`](planning/implementation-plan.md) |
| 验证记录 | [`verification/`](verification/)（M0–M4、miner、v1.1.0） |
| 第三方库许可证 | [`references/licenses/`](references/licenses/) |

## 仓库关系（已变，旧文档里的说法作废）

`game-framework` 现在是**指向本目录的软链**：

```
auto-games/defold/game-framework -> defold-game-framework
```

即：只有一个仓库、一份 `.git`。旧 SOP 里「`game-framework` 是本地工作副本、没有 `.git`，
改完要同步到 `defold-game-framework` 再提交」这套**已完成历史使命**，现在改成：

```
改文件 → git commit（+ 需要时打 tag）→ 游戏侧改 dependencies#0 一行
```

## 发布物（两种，别混用）

| 形态 | 产出 | 内容 | 用途 |
|---|---|---|---|
| 库 ZIP（瘦） | `python3 scripts/export-libraries.py` → `dist/libraries/defold-framework-<ver>.zip` | 只 `framework/` + 自动生成的 `game.project`（`[library] include_dirs = framework`） | 正式依赖，真正「只用 framework」 |
| 整仓 ZIP | GitHub codeload `<repo>/zip/<sha>` | `framework/` + `docs/` + `examples/` + `tests/` + `scripts/` + `game_modules/` | 快速迭代；注意 `examples/` 会一起进依赖 |

注意：**GitHub 的 codeload ZIP 不认 `.gitattributes` 的 `export-ignore`**，
所以没法靠 export-ignore 把 `examples/`、`templates/` 摘出去——要瘦只能换发布物。

实测（整仓 `83e390c`，332 KB）：`examples/` 70 文件、`framework/` 48、`docs/` 30、
`tests/` 10、`game_modules/` 7、`scripts/` 6；这些未被 `require` 的资源**不会进 build 产物**，
只增加下载量。

## 当前状态

- 框架 commit：`83e390c08e729f93cc09ac6ccd626358246dae20`（含 `framework/docs/`）
- 引擎：Defold 1.14.1（`engine_sha = ee283d4d…`）
- 阶段：v1.1.0 可用性修复已完成，详见 [`verification/v1.1.0-fixes.md`](verification/v1.1.0-fixes.md)
- 设计/历史：`architecture/`、`planning/`、`references/studio-proposal.md`
