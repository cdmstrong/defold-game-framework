# AGENTS.md — 框架仓库工作约定

项目根：`/Users/chendongming/coding/auto-games/defold/defold-game-framework`
（`../game-framework` 是软链，指向同一个目录、同一个 `.git`，别当成两个仓库）

**这是框架库 + 游戏模板仓库，不是游戏项目。** 游戏项目是独立仓库（`../platformer-game`、
`../miner-game` 等），只通过 `game.project` 的 `dependencies#0` 引用这里的 `framework/`。

## 一、用户说"新建游戏" → 只走脚本，不手抄 rsync

```bash
cd /Users/chendongming/coding/auto-games/defold/defold-game-framework
python3 scripts/new-game.py --type platformer --name my-game --title "我的游戏"
```

执行前只需确认三件事（其余都有默认值）：

| 参数 | 说明 | 默认 |
|---|---|---|
| `--type` | `templates/<type>/`，现有 `platformer`（完整项目骨架）、`miner`（片段，不能独立跑） | 无，必须给 |
| `--name` | 新目录名，也是 `app_id` / 配置前缀 | 无，必须给 |
| `--title` | `game.project` 的显示名 | 同 `--name` |
| `--dst` | 父目录 | `/Users/chendongming/coding/auto-games/defold` |

脚本一条命令做完：复制骨架 → 改写标识（`climber.` / `_G.SKY_SESSION` / title / app_id）→
`version` 归 `0.1.0` → 写 `dependencies#0`（自动取**已推送**的 `fw-dist` sha）→ 拷 22 MB 字体
+ `bob.jar` → `resolve` + `build` 断言 framework luac → `git init` + 首提。

常用变体：`--dry-run`（只看计划）、`--no-build --no-git`（先出骨架）、
`--framework-url <url>`（临时指向别的快照）。

**硬约束**：`new-game.py` 里不许出现任何具体游戏的名字。复制排除、标识替换、验收阈值
全部读 `templates/<type>/template.json`；加新模板 = 加目录 + manifest，不改脚本。

## 二、改框架 → 必须重发快照

文档也在 `framework/` 里（`framework/docs/`），所以**改文档一样要重发**：

```bash
# 改 framework/**  →  commit  →  推送 master
python3 scripts/publish-framework.py          # 造 fw-dist 快照 + 推送 + 打印新 URL
# 然后把用到的游戏仓库 dependencies#0 换成新 sha，重新 resolve + build
```

`publish-framework.py` 要求 `framework/` 无未提交改动；它用 `git commit-tree` 造**无父提交**
快照（树 = 生成版 `game.project` + `framework/`），不动工作区。dist 只含这两样，
`templates/`、`docs/`、`scripts/` 永远不进依赖。

## 三、其余入口

| 要做的事 | 命令 / 位置 |
|---|---|
| 从真实项目刷新模板快照 | `python3 scripts/snapshot-template.py --from ../platformer-game --name platformer` |
| 查某个 Defold 特性的官方写法（animation / physics / gui / tilemap / factory…） | `../examples-ref/`（Defold 官方示例库 defold/examples 的本地副本，CC0，**不进 git**；140 个独立小项目，每个自带 `game.project`，要跑哪个就单独打开那个子目录。更新：从 GitHub 拉 defold/examples 重新覆盖该目录） |
| 校验库分层没串味 | `python3 scripts/check-layers.py`（最小消费者，必须 PASS） |
| 导出离线库 ZIP | `python3 scripts/export-libraries.py` |
| 新建项目的完整 SOP / 手工兜底 | `framework/docs/project-bootstrap.md` |
| 踩坑记录索引（排障第一步） | `framework/docs/README.md` |
| 模板契约与字体说明 | `templates/README.md`、`templates/*/template.json` |
| 脚本清单 | `scripts/README.md` |

## 四、验证判据（别被退出码骗）

1. **`bob resolve` 有库下载失败仍返回 0** —— 必须 `grep -E "SEVERE|Failed to fetch"`，
   否则 build 复用旧缓存，产物看着"成功"其实缺模块（报 `the Lua module '/framework/core/app.lua' can't be found`）。
2. **刚推完的 commit 有索引延迟** —— 立刻 resolve 可能 `Failed to fetch`，几秒后 codeload 才 200，重试即可。
3. **编译成功看 `build/**/framework/**/*.luac` 数量**（当前 15 个），不看"Building…100%"。
4. `require` 必须是字面量（`require "framework.core.app"`）；`pcall(require, name)` 会被 bob 静态分析漏掉，
   检查变空转。
5. 产物里不该出现 `templates/`、`docs/`、`scripts/`——出现就是依赖指错到整仓 ZIP 了。
