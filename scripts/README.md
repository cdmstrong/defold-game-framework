# scripts/

框架仓库的辅助脚本。全部为命令行工具，不参与 Defold 构建。

| 脚本 | 作用 | 依赖 |
| --- | --- | --- |
| `export-libraries.py` | 把 `framework/` 与 `game_modules/tycoon/` 导出为两个独立库 ZIP；framework 版本号自动跟随本仓库 git tag（可用 `--framework-version` / `--tycoon-version` 覆盖） | Python 3，无第三方包 |
| `check-layers.py` | 构造一个只引用这两个库 ZIP 的隔离消费者项目，验证单向依赖没有泄漏（体系中立层 vs 品牌层） | Python 3 + 本地 `bob.jar` |
| `project.py` | M0 入口：按 `docs/planning/dependencies.json` 锁定依赖版本、校验 SHA256、生成/校验 `game.project` 依赖行 | Python 3 |
| `check-miner.mjs` | 浏览器端 miner 集成回归（挖矿→雇工→升级→广告翻倍→存档回读） | Node + playwright |

## 用法

```bash
cd defold-game-framework

# 导出两个库 ZIP 到 ../framework-releases/
python3 scripts/export-libraries.py

# 隔离校验（需要 bob.jar，路径见脚本内默认值）
python3 scripts/check-layers.py

# 依赖锁定/校验
python3 scripts/project.py --help
```

## 注意

- `check-miner.mjs` 里写死了旧的本地工作区路径（`.../defold/game-framework`）与浏览器安装目录。
  该工作区已废弃，如需继续用这个回归脚本，请把 `root` / playwright 路径改成实际项目目录。
- `check-layers.py` 会临时起本地 HTTP 服务（默认 127.0.0.1:8899 段）供 bob 解析 ZIP 依赖。
