# 挖矿大亨（Miner Tycoon）— 游戏计划

用 game-framework 框架制作的一款「点击矿工挂机」多页面完整小游戏，用于验证框架完整链路。

## 一、玩法定位

点击挖矿 → 攒金币 → 雇佣矿工自动生产 → 升级（点击收益 / 矿工产量 / 离线收益）→ 广告复活/翻倍奖励 → 存档跨会话。

核心数值（参考用户的铜矿经济偏好，投产比需真实落到代码）：

| 项 | 初始 | 成长 |
|---|---|---|
| 点击收益 | 1 金币/次 | 升级成本 ×1.6，收益 +1/次 |
| 矿工（雇佣后自动生产） | 首名 10 金币，1 金币/秒 | 每名成本 ×1.5，产量 +1/秒 |
| 离线收益 | 关游戏期间按矿工产出 50% 累计，上限 8 小时 | — |

## 二、页面结构（Monarch 导航）

1. **mine（主页）**：金币余额、每秒产出、点击挖矿区、矿工列表/雇佣按钮、顶部进入商店/升级/设置。
2. **shop（商店）**：雇佣矿工（显示成本/当前数量/总产量）。
3. **upgrade（升级）**：升级点击收益、矿工产量、离线收益系数（显示当前等级/下一级成本/效果）。
4. **settings（设置）**：音量/静音/语言（复用框架 Settings/Audio/Localization）+ 看广告（复活翻倍）。
5. **dialog（弹窗）**：离线收益结算弹窗、广告结果弹窗（复用框架 dialog + pause）。

## 三、复用的框架能力

- **Monarch 导航栈**：`framework/ui/ui_manager` + `adapters/monarch`，多页面 + 模态弹窗 + 返回。
- **存档**：`save_manager` + `storage.defold`，金币/矿工/升级等级跨会话持久化（含离线收益结算）。
- **Settings/Audio/Localization**：设置页音量/静音/语言，复用既有服务。
- **平台检测/广告/Analytics**：M4 的 `reward_ad`（mock 广告发金币翻倍）、`analytics`（埋点点击/升级/雇佣）、`platform`（browser/desktop 检测）。
- **UI 组件**：`button` / `currency_bar` / `progress_bar` / `item_card` / `toast` / `tab`。

## 四、目录结构（新增，不动 framework）

```
examples/miner/
├── game.lua              # 游戏状态机 + 数值逻辑（纯 Lua 可测）
├── bootstrap.script      # 组装服务 + 游戏主循环 + 离线收益结算
├── bootstrap.go
├── context.lua
├── view.lua              # 各页面渲染 + 按钮绑定
├── main.collection       # 入口（替换 bootstrap main_collection 指向）
├── mine/{go,gui,gui_script,collection,collectionproxy,route.go}
├── shop/{...}
├── upgrade/{...}
├── settings/{...}
└── dialog/{...}
```

## 五、关键设计

- **游戏逻辑与 UI 分离**：`game.lua` 是纯数值状态机（点击/雇佣/升级/离线结算），可纯 Lua 单测；`view.lua` 只渲染。
- **广告奖励**：mock 广告 rewarded → `grant_once` 发「双倍金币」一次；广告期间 `pause:acquire("ad")` 暂停主循环。
- **离线收益**：启动时读 `saved_at`，按矿工产量 × 50% × 离线秒数（上限 8h）结算，弹 dialog 展示。

## 六、验证

1. 纯 Lua 单测 `tests/lua/test_miner.lua`：点击/雇佣成本成长/升级成本成长/离线收益结算上限/存档往返。
2. HTML5 集成 `scripts/check-miner.mjs`：点击挖矿 → 雇佣 → 升级 → 看广告翻倍 → 刷新存档恢复 → 离线收益弹窗。
3. M1 回归不破坏。

## 七、验收边界（先出计划，逐步实现）

按用户习惯：先出这份计划文档，确认后再逐项实现。一次一项，简短编号决策。
