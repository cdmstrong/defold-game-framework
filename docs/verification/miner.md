# 挖矿大亨（Miner Tycoon）验证记录

日期：2026-11-18（Asia/Shanghai）。环境：本机 macOS / Apple Silicon，Defold 与 Bob 1.14.1，engine SHA `ee283d4dad9fa451dd6399d83602e1dc25133681`，Lua 5.5.1。

用 game-framework 框架制作的一款「点击矿工挂机」多页面完整小游戏，验证框架完整链路（Monarch 导航、UI 组件、存档/迁移、Settings/Audio/Localization、平台检测/广告/Analytics）。

## 玩法与数值

点击挖矿 → 攒金币 → 雇佣矿工自动生产 → 升级（点击收益/矿工产量/离线收益）→ 广告翻倍 → 存档跨会话 + 离线收益结算。

| 项 | 初始 | 成长 |
|---|---|---|
| 点击收益 | 1 金币/次 | 升级成本 50 × 1.6^等级，收益 +1/次 |
| 矿工 | 首名 10 金币，1 金币/秒 | 成本 10 × 1.5^数量，产量 1×(1+等级×0.1)/秒 |
| 离线收益 | 系数 0.5 | 升级成本 200 × 2.0^等级，系数 +0.1/级，上限 8 小时 |

## 产物

- `examples/miner/game.lua` — 游戏状态机（纯 Lua 可测）：点击/雇佣/升级/离线结算/广告翻倍/存档校验。
- `examples/miner/bootstrap.script` — 组装 framework 全部服务 + 游戏主循环（自动生产累积器）+ 离线收益结算 + 低频操作即时存档。
- `examples/miner/view.lua` — 各页面渲染 + 按钮绑定（mine/shop/upgrade/settings/dialog）。
- `examples/miner/context.lua` — 组合根状态持有。
- `examples/miner/` 其余：5 个页面的 `.go` / `.gui` / `.gui_script` / `.collection` / `.collectionproxy` / `_route.go` + `main.collection` + `bootstrap.go`。
- `tests/lua/test_miner.lua` — 11 个纯 Lua 单测。
- `scripts/check-miner.mjs` — HTML5 集成验证。
- `assets/fonts/zh.font` — 补充 42 个中文字符（挖/矿/大/亨/商/店/升/级/工/雇/佣/领/取/消/看/广/告/翻/倍/离/线/收/益/秒/获/得/金/币/产/量/名/产/出 等）。
- `game.project` — `main_collection` 切换到 `/examples/miner/main.collectionc`。
- `docs/planning/miner.md` — 游戏计划文档。

## 已通过

### 纯 Lua 单测（11 用例全绿，累计 59 用例）

| 覆盖 |
|---|
| 点击加金币、点击升级收益 +1 与成本 ×1.6、升级钱不够、矿工成本 ×1.5 与雇佣、矿工升级产量、离线结算 8 小时上限、无矿工离线为 0、首跑离线为 0、广告翻倍、存档校验、旧档缺字段兜底 |

### 集成（真实 HTML5 引擎）

| 项目 | 证据 |
|---|---|
| 首次加载 | `MINER_LOAD source=default coins=0 miners=0` |
| 点击挖矿 | `MINER_CLICK gain=1 coins=1` |
| 雇佣失败（钱不够） | `MINER_HIRE_FAIL insufficient` |
| 雇佣成功 | `MINER_HIRE cost=10 miners=1` |
| 广告翻倍 | `MINER_AD_GRANT gain=9 coins=18` |
| 存档跨刷新 | reload `MINER_LOAD source=archive coins=18 miners=1` |
| 中文渲染 | 截图确认标题/按钮/文案无方框乱码 |

截图：`logs/miner/miner-mine.png`、`logs/miner/miner-settings.png`。

## 修复与关键结论

1. **HTML5 刷新时 `final()` 不一定执行**：初版只在 auto-save（5s）+ `final()` 存档，导致雇佣后立即刷新丢失 `miners=1`（回到 `miners=0`）。修复：低频操作（雇佣/升级/广告）后**立即 persist**，高频点击靠 auto-save 兜底。
2. **Monarch 转场期间点击被 `ui:is_busy()` 拦截**：`MINER_VIEW_INIT` 打印时转场动画（0.12s）未完成，立即点击无效。集成脚本在页面 ready 后加 400ms 等待转场 settle。
3. **`.font` 字符集需补充游戏专属中文**：复用 M3 的 zh.font 字符集（不含挖矿相关字），补充 42 字，仍避开 `"`/`\`。
4. **游戏逻辑与 UI 分离**：`game.lua` 纯数值状态机可独立单测，`view.lua` 只读快照渲染，`bootstrap` 驱动 tick 与存档。

## 界限

- 广告用 mock（`m4.ad_platform=mock`）验证状态机；真实 taptap/233 广告需平台账号与广告位。
- 音频 backend 为无声音资源的记录式空实现。
- 离线收益上限 8 小时、系数 0.5 为初始设定，未做长线数值平衡调优（可后续按用户偏好微调）。

## 重现

```sh
# 纯 Lua 单测
python3 scripts/project.py unit

# HTML5 集成
python3 scripts/project.py bundle-html5
python3 scripts/project.py serve        # 保持运行
node scripts/check-miner.mjs
```

完整日志在 `logs/miner/`，截图在 `logs/miner/miner-*.png`。
