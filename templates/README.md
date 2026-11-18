# templates/ — 游戏骨架与参考实现

新游戏的起点。**本目录不进游戏依赖**：发布用的 `fw-dist` 分支只含 `framework/` + `game.project`，
所以这里的骨架再大也不会跑到别人的项目里（`framework-releases/` 的整仓 ZIP 时代已经结束）。

## 新建游戏（唯一入口）

不要手抄 rsync 清单，跑脚本：

```bash
cd /Users/chendongming/coding/auto-games/defold/defold-game-framework
python3 scripts/new-game.py --type platformer --name my-game --title "我的游戏"
```

它按本目录的 `template.json` 复制骨架、改写标识、归零 `version`、写已发布的 `fw-dist` 依赖、
拷字体与 `bob.jar`，再真实 `resolve` + `build` 断言，最后 `git init` 首提。
`--dry-run` 只看计划。完整说明见 `../AGENTS.md` 第一节。

## 两种骨架，结构不同，别混

| `skeleton` | 含义 | 怎么用 |
|---|---|---|
| `project` | 完整项目骨架，自带 `game.project` / `main.collection` | 整份复制成新项目，按玩法裁剪 |
| `fragments` | 片段集合，没有 `game.project` | 拷进已有项目的子目录，路径保持不变 |

## 清单

| 模板 | 类型 | 内容 | manifest |
|---|---|---|---|
| `platformer/` | `project` | 横版跳跃 / 跑酷：`main.collection` + `menu/game/hud` 三个 collection proxy，session 单点存档，带冒烟钩子 | [`template.json`](platformer/template.json) |
| `miner/` | `fragments` | 经营 / 挂机：挖矿、商店、设置、对话框 4 场景 + 路由，接 `game_modules/tycoon` 两层 UI | [`template.json`](miner/template.json) |
| `ui-demo/` | `fragments` | 框架 UI 组件演示（button / tab / scroll / toast / confirm_dialog） | — |

`template.json` 是给脚本读的契约：骨架类型、需要改写的标识（`replace`）、要归零的字段
（`reset`）、前置依赖（`requires`）、验收断言（`verify`）。加新类型 = 加一个模板目录 + 一份 manifest，
脚本不用改。

## 字体不在仓库里

所有骨架的 `.gui` 都引用 `zh` 字体，需要 `assets/fonts/zh.font` + `ArialUnicode.ttf`。
`zh.font`（570 B，含字形表）随模板提供；**`ArialUnicode.ttf` 约 22 MB，不进 git**，
从任一游戏项目拷：

```bash
cp ../platformer-game/assets/fonts/ArialUnicode.ttf templates/platformer/assets/fonts/
```

少了 ttf，`zh` 字体编译不过，但骨架结构照旧可以对照。

## 刷新 platformer 快照

`platformer/` 是 Sky Climber 的骨架快照，源头是 `/Users/chendongming/coding/auto-games/defold/platformer-game`。
那边改完想同步过来：

```bash
python3 scripts/snapshot-template.py --from ../platformer-game --name platformer
```

脚本按 `template.json` 的 `excludes` 复制，不碰 `.git`、构建产物、字体二进制和该游戏的设计文档。

## 为什么 `miner/` 不能独立跑

它原本跑在已删除的 `game-framework/` 工作区里，现在缺两样：字体，以及 `[bootstrap] main_collection`
（本仓库的 `game.project` 是库配置，没有入口）。要跑就给个临时入口指向 `templates/miner/main.collection`，
或者直接看 `miner-game` 独立仓库。
