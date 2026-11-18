# scripts/

框架仓库的辅助脚本。全部为命令行工具，不参与 Defold 构建。

| 脚本 | 作用 | 依赖 |
| --- | --- | --- |
| `publish-framework.py` | **发布瘦依赖**：把 `framework/` + 生成的 `game.project` 提交到 `fw-dist` 分支并推送，打印游戏要用的 `dependencies#0 = codeload…/zip/<sha>` | Python 3 + git |
| `export-libraries.py` | 把 `framework/` 与 `game_modules/tycoon/` 导出为两个独立库 ZIP；framework 版本号自动跟随本仓库 git tag（可用 `--framework-version` / `--tycoon-version` 覆盖） | Python 3，无第三方包 |
| `check-layers.py` | 构造只引用这两个库 ZIP 的最小消费者项目（无 GUI、无字体），验证 `require` 可达、编译通过、`templates/` 没漏进依赖 | Python 3 + 本地 `bob.jar` |
| `snapshot-template.py` | 按 `templates/<name>/template.json` 的 `excludes` 从真实游戏项目刷新骨架快照 | Python 3 |
| `project.py` | M0 入口：按 `docs/planning/dependencies.json` 锁定依赖版本、校验 SHA256、生成/校验 `game.project` 依赖行 | Python 3 |
| `check-miner.mjs` | 浏览器端 miner 集成回归（挖矿→雇工→升级→广告翻倍→存档回读） | Node + playwright |

## 用法

```bash
cd defold-game-framework

# 改完 framework/ 后发布瘦依赖（commit 会自动推 fw-dist 分支）
python3 scripts/publish-framework.py --dry-run   # 先看计划
python3 scripts/publish-framework.py             # 真发布，输出新 dependencies#0

# 导出两个库 ZIP（离线分发 / 自建 HTTP 用）
python3 scripts/export-libraries.py

# 打包正确性校验（先 export）
python3 scripts/check-layers.py

# 刷新模板快照
python3 scripts/snapshot-template.py --from ../platformer-game --name platformer

# 依赖锁定/校验
python3 scripts/project.py --help
```

## 注意

- `publish-framework.py` 要求 `framework/` 没有未提交改动（否则发出去的快照和本地不一致）。
  它用 `git commit-tree` 直接造提交，**不动工作区**，所以可以随时跑。
- `fw-dist` 分支的提交没有父历史，是一条独立快照；要回滚依赖就指回旧的 dist sha。
- `check-layers.py` 会临时起本地 HTTP 服务（随机端口）供 bob 解析两个 ZIP；
  上游 druid/monarch/event 仍走 codeload，首次运行需要联网。
- `check-miner.mjs` 里写死了旧的本地工作区路径（`.../defold/game-framework`）与浏览器安装目录。
  该工作区已废弃（现在只是软链），如需继续用这个回归脚本，请把 `root` / playwright 路径改成实际项目目录。
