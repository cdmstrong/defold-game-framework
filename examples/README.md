# examples/

仓库内参考示例，**不参与库导出**（`[library] include_dirs` 只含 `framework`，
游戏依赖本库时不会拉到这里的代码）。

| 示例 | 内容 |
| --- | --- |
| `miner/` | 经营类完整示例：挖矿/商店/升级/设置/对话框 5 个场景 + 路由，已接入 `game_modules/tycoon` 两层 UI |
| `ui_demo/` | 框架 UI 组件演示（button / tab / scroll / toast / confirm_dialog 等） |

## 本地跑示例

这两个示例原本跑在已删除的 `game-framework/` 工作区里，**缺两样东西**才能独立运行：

1. **字体**：所有 `.gui` 引用 `zh` 字体，需要 `assets/fonts/zh.font` + `ArialUnicode.ttf`。
   可从一个游戏项目（如 `miner-game/assets/fonts/`）拷过来，体积约 16 MB，因此没有放进本仓库。
2. **`[bootstrap] main_collection`**：本仓库的 `game.project` 是库配置（无入口），
   要跑示例需临时指向 `examples/miner/main.collection`。

更推荐的做法：直接看 `miner-game` 仓库（独立游戏仓库，已配好字体与入口），
本目录仅作代码参考。
