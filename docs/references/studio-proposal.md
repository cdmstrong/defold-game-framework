# Defold 游戏开发框架：落地方案

你的选择是：

- 主引擎：Defold
    
- 项目模式：每个游戏独立工程
    
- 复用方式：公共框架 + 可插拔模块 + 类型模板
    
- 开发方式：AI 负责生成、修改、构建和测试
    
- 发行目标：H5 聚合平台优先，同时兼容 iOS、Android
    

我建议把它设计成一个小型的 AI Game Studio，而不只是几个游戏模板。

最重要的原则是：

每个游戏独立运行、独立构建、独立发布；公共能力统一维护、版本化复用。

不要把所有游戏塞进同一个 Defold 工程，也不要一开始就做成一个庞大的通用游戏引擎。

## 1. 先确定技术架构：三种东西分开管理

我建议你不要把「框架、模板、游戏模块」混在一起。

|类型|是什么|是否被游戏运行时引用|
|---|---|---|
|Framework|通用基础能力|是|
|Modules|可复用的玩法系统|是，按需引用|
|Templates|新游戏的起始工程|复制后独立开发|

例如：

- Framework：存档、UI、广告、音频。
    
- Modules：经济系统、生产系统、背包、棋盘、碰撞。
    
- Templates：Tycoon、Arcade、Puzzle。
    

模板不是一个庞大的运行时依赖库，而是一个可以复制的项目骨架。

这点非常重要。模板需要随着实践不断演进，但已经发布的游戏不应该因为模板更新而被动改变。

## 2. Defold 的项目组织方式

Defold 本身支持 Library Project，可以把一个项目里的资源提供给其他项目使用，通过项目依赖的方式引入。它比把所有公共代码复制进每个游戏更容易统一维护。

Defold

我建议使用下面这种组织方式：

game-studio（你的工作空间）

GitHub Organization 或本地工作目录

公共库仓库

`defold-framework`

基础框架、UI、存档、平台适配

`defold-modules`

经济、生产、升级、棋盘、物理等模块

模板仓库

Tycoon

经营

Arcade

街机

Puzzle

益智

独立游戏仓库

supermarket-game

restaurant-game

phone-repair-game

stacking-game

实际可以放在 GitHub 的同一个 Organization 下，每个项目单独一个仓库。

### 为什么不建议所有东西放在一个仓库？

因为你未来可能同时开发十几个游戏：

- 游戏 A 使用 Framework 1.0。
    
- 游戏 B 使用 Framework 1.1。
    
- 游戏 C 使用 Framework 1.2。
    

如果某次修改存档系统导致旧游戏出现问题，不应该影响其他游戏。

所以每个游戏都应该固定公共库版本，经过验证后再升级。

## 3. 公共框架具体目录

这是我建议你先创建的 `defold-framework` 项目。

```
defold-framework/
│
├── game.project
├── README.md
├── CHANGELOG.md
│
├── framework/
│   ├── core/
│   │   ├── app.lua
│   │   ├── scene_manager.lua
│   │   ├── event_bus.lua
│   │   ├── state.lua
│   │   └── constants.lua
│   │
│   ├── ui/
│   │   ├── ui_manager.lua
│   │   ├── screen.lua
│   │   ├── dialog.lua
│   │   ├── toast.lua
│   │   ├── components/
│   │   │   ├── button.lua
│   │   │   ├── progress_bar.lua
│   │   │   ├── tab.lua
│   │   │   └── currency_bar.lua
│   │   └── layouts/
│   │
│   ├── data/
│   │   ├── config.lua
│   │   ├── json.lua
│   │   └── localization.lua
│   │
│   ├── save/
│   │   ├── save_manager.lua
│   │   ├── serializer.lua
│   │   └── migration.lua
│   │
│   ├── platform/
│   │   ├── platform.lua
│   │   ├── browser.lua
│   │   ├── mobile.lua
│   │   └── safe_area.lua
│   │
│   ├── monetization/
│   │   ├── ads.lua
│   │   ├── ad_config.lua
│   │   └── purchase.lua
│   │
│   ├── services/
│   │   ├── audio.lua
│   │   ├── analytics.lua
│   │   └── network.lua
│   │
│   └── debug/
│       ├── debug_menu.lua
│       ├── logger.lua
│       └── profiler.lua
│
└── tests/
    ├── test_event_bus.lua
    ├── test_save.lua
    └── test_ui.lua
```

这里有几个设计要求：

第一，所有模块尽量使用纯 Lua 逻辑。

比如经济计算不应该依赖 Defold GUI 节点。这样既容易测试，也容易让 AI 理解和修改。

第二，平台能力通过统一接口暴露。

例如：

```
-- 游戏逻辑只调用统一接口
Ads.show_rewarded("double_income", function(success)
    if success then
        Economy.add_money(100)
    end
end)
```

底层再判断：

- H5：Poki / CrazyGames / Playgama。
    
- iOS：对应移动广告 SDK。
    
- Android：对应移动广告 SDK。
    
- 无广告版本：返回不支持或执行明确的回调策略。
    

不要在游戏玩法代码里直接调用不同平台的 SDK。

第三，UI 和玩法系统分开。

GUI 负责展示，Lua 业务模块负责数据计算。不要让一个 GUI Script 同时承担存档、经济、升级、广告和所有按钮事件。

## 4. 玩法模块库怎么拆？

单独创建 `defold-modules`。

```
defold-modules/
│
├── common/
│   ├── timer/
│   ├── random/
│   ├── math/
│   └── object_pool/
│
├── tycoon/
│   ├── economy/
│   ├── production/
│   ├── upgrade/
│   ├── inventory/
│   ├── employee/
│   ├── customer/
│   ├── order/
│   ├── offline_income/
│   └── unlock/
│
├── arcade/
│   ├── score/
│   ├── combo/
│   ├── difficulty/
│   ├── revive/
│   └── level/
│
├── puzzle/
│   ├── board/
│   ├── grid/
│   ├── match/
│   ├── merge/
│   ├── hint/
│   └── move/
│
└── strategy/
    ├── battle/
    ├── tower/
    └── unit/
```

注意：这里不是要求你第一天把所有模块全部写出来。

我建议先实现通用性明确的模块，再在真实游戏中验证。比如 `employee`、`customer`、`production` 并不一定所有经营游戏都需要，不能为了抽象而抽象。

### 模块接口应该统一

例如经济系统：

```
local Economy = {}

function Economy.create(config)
    -- 创建经济状态
end

function Economy.get_balance(state, currency)
end

function Economy.add(state, currency, amount)
end

function Economy.spend(state, currency, amount)
end

function Economy.can_afford(state, currency, amount)
end

return Economy
```

升级系统：

```
local Upgrade = {}

function Upgrade.get_cost(config, level)
end

function Upgrade.get_value(config, level)
end

function Upgrade.can_upgrade(state, config)
end

function Upgrade.apply(state, config)
end

return Upgrade
```

这些模块应该尽量不依赖 `msg.post()`、GUI 节点或游戏对象地址。需要与 Defold 场景交互时，再由游戏项目中的 Controller 负责连接。

## 5. 游戏项目本身应该长什么样？

以你准备开发的手机维修游戏为例。

phone-repair-game/

一个完整、独立的 Defold 工程

```

phone-repair-game/
├── game.project
├── README.md
├── AGENTS.md
│
├── main/
│   ├── main.collection
│   └── bootstrap.go
│
├── src/
│   ├── game/
│   │   ├── game_controller.script
│   │   ├── game_config.lua
│   │   └── game_state.lua
│   │
│   ├── systems/
│   │   ├── repair_system.lua
│   │   ├── customer_system.lua
│   │   └── order_system.lua
│   │
│   ├── data/
│   │   ├── phones.lua
│   │   ├── parts.lua
│   │   └── upgrades.lua
│   │
│   └── ui/
│       ├── home.gui
│       ├── repair.gui
│       ├── shop.gui
│       └── result.gui
│
├── assets/
│   ├── atlases/
│   ├── images/
│   ├── fonts/
│   ├── sounds/
│   └── particles/
│
├── collections/
├── gameobjects/
├── input/
├── tests/
│
└── docs/
    ├── GDD.md
    └── ACCEPTANCE.md
  
```

这个游戏依赖的公共模块可以是：

|来源|引入内容|
|---|---|
|Framework|Core、UI、Save、Ads、Audio|
|Modules|Economy、Inventory、Upgrade|
|游戏自身|Repair、Customer、Order|

Defold 中游戏对象、组件、Collection 和脚本资源有各自的组织关系，资源引用也会影响实际构建，因此目录设计不能只按普通 Lua 项目思路处理。

Defold+1

## 6. UI 系统：我建议单独投入精力建设

考虑到你之前就觉得 Defold 的 UI 编辑器不够方便，我认为这是整个框架中最值得提前投入的地方。

我建议采用：

- Druid：基础 UI 控件。
    
- Monarch：页面、弹窗和转场管理。
    
- 自己封装一套业务组件和主题系统。
    

这两者不是 Defold 官方内置功能，而是社区工具，具体版本需要在开始建设时固定。

[Druid - Component GUI Framework - The Defoldmine - Defold game engine forum](https://images.openai.com/static-rsc-4/RK-3wUYZ9Q39t19udFZKrYyHQ-kO6kDuwQ89iavVyihBJkhG0CN_XQL6bc3eXjPebroDpIXLHS4xIMeQvQpFjOvp_KYEh3PCujl8ZDelEzM0liYoR4ouC9vYAD6VMYK89SVF162AtswaLYdGw4tWQ93JcnCwZ1HU1ZX3pCNHBVc?purpose=inline)

[Idle Tycoon clicker by eSolutions](https://images.openai.com/static-rsc-4/-mNxf2sCoojhG2_iEgSlm9Pd2XcV_gURn_3ierIix899LIccJdESs1q5vO-Wo9nDEf9Z5SlX8UYvTA5VozpWS8P9TagY9ydaaQX_N_JSJlt_Hku2kw1fDX9SJqPJOxZetFa6_NzjDM4nJnqS746Xexj8E6sdtXNyveVW_N7r6ks?purpose=inline)

[Tips To Play Idle Bank Tycoon - Updated For 2023 - Talk Android](https://images.openai.com/static-rsc-4/NSqG8AD-ZzEDvrjttrlGzhieqlafxNtlBcekAd1XFLYd9AFekKquJhfsqQDZqjnhYSOui-wjmBxapCI76k_gq2sMlt1msgpFGpPBWomV6o5308LEzF8UGHPnZsEdUNC95mTrCjoAqiU8XeA1J8CdNpwLKyu6hqEekmSNYn4m5u0?purpose=inline)

9

### UI 分成三层

|层级|内容|例子|
|---|---|---|
|Base UI|基础控件|Button、Text、Scroll、Slider|
|Common UI|通用业务组件|CurrencyBar、ItemCard、RewardDialog|
|Game UI|游戏专属界面|RepairPanel、SupermarketPanel|

### 建立统一主题配置

例如：

```
return {
    colors = {
        primary = "#4F8EF7",
        background = "#F5F6FA",
        panel = "#FFFFFF",
        text = "#20232A",
        success = "#37B77A",
        danger = "#F05A5A",
    },

    spacing = {
        xs = 4,
        sm = 8,
        md = 16,
        lg = 24,
        xl = 32,
    },

    radius = {
        card = 12,
        button = 10,
        dialog = 18,
    }
}
```

不同游戏可以切换不同主题，不需要重写整个 UI。

我的建议是先做一个 UI Demo 工程，把按钮、卡片、列表、弹窗、Tab、滚动列表、弹出动画都跑通。 以后每款游戏再按风格调整。

## 7. 模板仓库如何设计？

模板只负责提供可以立即运行的起始项目。

例如 `template-tycoon`：

```
template-tycoon/
│
├── game.project
├── main/
│   └── main.collection
│
├── scenes/
│   ├── boot.collection
│   └── game.collection
│
├── gui/
│   ├── home.gui
│   ├── shop.gui
│   └── offline_reward.gui
│
├── scripts/
│   ├── game_controller.script
│   └── ui_controller.gui_script
│
├── config/
│   ├── game_config.lua
│   ├── economy_config.lua
│   └── upgrade_config.lua
│
├── assets/
└── docs/
    └── TEMPLATE_GUIDE.md
```

模板中预先接入：

- 公共框架。
    
- 经营模块。
    
- 基础 UI。
    
- 一个示范生产设施。
    
- 一个升级界面。
    
- 一个离线收益弹窗。
    
- 一套可运行的存档。
    

复制后只需要改游戏内容，就能开始开发。

## 8. 公共模块怎么接入 Defold？

这里我建议你优先使用 Defold Library Project + Git 版本标签。

例如：

```
defold-framework
    v1.0.0
    v1.1.0
    v1.2.0

defold-modules
    v1.0.0
    v1.1.0
```

游戏工程在 `game.project` 中声明依赖，固定使用经过验证的版本。Defold 的 Library Project 就是为跨项目复用资源而设计的。

Defold

建议依赖关系：

```
game project
    │
    ├── defold-framework
    │       ├── core
    │       ├── ui
    │       ├── save
    │       ├── ads
    │       └── platform
    │
    └── defold-modules
            ├── economy
            ├── upgrade
            ├── production
            └── offline_income
```

初期不要拆成二十个 Git 仓库。两个公共库就够了。

等模块成熟、不同游戏确实需要不同版本组合时，再考虑拆分。

## 9. AI 自动开发流水线

这是你这套体系最终最有价值的部分。

Defold 官方已经提供了 Editor HTTP API、Bob CLI、Editor Scripts、运行时服务和自动化测试等多层自动化接口。官方也明确建议形成「检查 → 修改 → 验证 → 评估」的闭环。

Defold+1

我建议把流程设计成：

1. 输入游戏创意
    
    例如：开发一个废旧手机回收经营游戏。
    
2. AI 生成 GDD
    
    玩法循环、资源、升级、界面、广告位置。
    
3. 选择模板
    
    Tycoon。
    
4. 检查公共模块
    
    自动判断需要 Economy、Inventory、Upgrade、Offline。
    
5. 创建独立项目
    
    从模板生成新游戏工程，配置游戏名称和依赖版本。
    
6. AI 开发
    
    生成玩法、UI、素材引用和配置。
    
7. 自动构建与测试
    
    MCP + Bob + 自动化测试 + 截图检查。
    
8. 生成发布包
    
    HTML5、iOS、Android。
    

建议项目根目录放置一个 `AGENTS.md`，让 AI 每次进入项目都能知道：

```
# Game Development Rules

## Engine
- Defold
- Lua 5.1 compatible
- Use existing framework modules first

## Architecture
- Keep gameplay logic independent from GUI
- Do not duplicate existing framework features
- Do not modify framework dependencies without approval
- Use configuration-driven game balance

## Workflow
1. Read project architecture
2. Inspect available modules
3. Implement the requested feature
4. Build the project
5. Run tests
6. Inspect screenshots
7. Report changed files and verification results

## Quality
- No silent errors
- No hardcoded platform SDK calls in gameplay
- Save data must support version migration
```

AI 不应该每次都自行发明架构，而应该遵循这些规则。

## 10. 最终实施顺序

我不建议你现在同时开发三个模板。先用一个真实游戏把整个框架跑通。

## 第一阶段建设计划

按依赖顺序推进，完成一项再进入下一项

1. 建立 defold-framework
    
    第一优先级
    
    Core、Save、UI、Audio、Ads、Platform。
    
2. 建立 UI Demo
    
    Druid、Monarch、通用组件、主题配置、屏幕适配。
    
3. 建立 defold-modules
    
    Economy、Upgrade、Production、Inventory、Offline。
    
4. 建立 template-tycoon
    
    做出可以直接运行的经营游戏基础工程。
    
5. 用真实游戏验证
    
    选手机维修大亨或超市经营游戏，把模板改造成完整产品。
    
6. 建立 AI 自动化工具链
    
    MCP、Bob、自动构建、截图和交互测试。
    
7. 再建设 Arcade 和 Puzzle
    
    用第二、第三个模板扩充生产能力。
    

## 我建议现在先做的第一件事

先不要让 AI 直接创建整个 Game Studio。先把公共框架的第一版范围定死：

V1.0 建议范围

|模块|是否纳入 V1|
|---|---|
|Core 生命周期|必须|
|EventBus|必须|
|UI Manager|必须|
|Druid 基础控件|必须|
|Monarch 页面管理|必须|
|Save / Migration|必须|
|Audio|必须|
|Ads 抽象接口|必须|
|Platform Adapter|必须|
|Localization|必须|
|Analytics|暂时简单封装|
|网络、云存档|暂缓|
|热更新|暂缓|
|复杂 3D 系统|暂缓|

最关键的架构原则：先把公共框架做成稳定的 Defold Library Project，再把玩法模块独立出来。

这样你后面每开发一个游戏，AI 只需要选择模板、组合模块、填充游戏内容，而不是重新设计整个工程。

接下来最有价值的产出，是把 `defold-framework` 的第一版接口、Lua 模块代码、Druid/Monarch 集成方式和 `game.project` 依赖配置全部具体化，形成可以直接交给 Codex 或 Claude Code 创建的工程实施规范。