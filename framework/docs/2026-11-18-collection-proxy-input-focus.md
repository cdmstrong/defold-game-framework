# collection proxy 场景内点击完全无反应（输入焦点）

- 日期：2026-11-18
- 引擎 / 平台：Defold 1.14.1 / macOS
- 项目：Sky Climber v0.4.0（`/Users/chendongming/coding/auto-games/defold/platformer-game`）
- 关联 commit：`88f7219`（修复）、`67f65f8`（同轮其他修复）

## 1. 现象与复现步骤

v0.4.0 把主页 / 对局从主集合拆成两个 collection proxy 子场景后，主页「开始游戏」按钮
点击毫无反应：没有任何回调、没有日志、没有报错。购买按钮同样无反应。
子场景里 `.script` 与 `gui_script` 都一样；init 里直发 `acquire_input_focus`、
GO 级转发、`timer.delay(0.1)` 延迟发送，三种写法全部无效。

v0.3 同样的代码可玩，差别只在 `world.script` 当时位于 `main.collection` 里。

## 2. 错误假设（走过的弯路）

> 「v0.4.0 把场景搬进 collection proxy 后，proxy 场景内所有脚本的
> `acquire_input_focus` 在 Defold 1.14.1 不生效 / 被丢弃」——写进了代码注释和提交信息。

这是**误判**。三种写法全部无效，真正原因是整棵子树没有接入输入栈，
而不是 acquire 这个 API 在特定版本失效。差一点就把一个配置错误当成引擎 bug，
并由此设计了不必要的「session 手动转发输入」中间层。

同期还叠加了一个真实代码 bug：`local function handle_input` 声明在 `on_message` 之后，
前向引用得到 nil（控制台报 `handle_input nil`），而 `luac -p` **不会报错**。
两个问题叠在一起，看起来更像「连引擎都不认」。

## 3. 三步查证结果

### 第 1 步：框架 docs 沉淀库

当时 `framework/docs/` 尚不存在 → 无记录可查。这正是建立本沉淀库的直接动因。

### 第 2 步：官方文档（找到明确答案）

- `https://defold.com/llms/manuals/collection-proxy.md` → **Caveats and common issues → Input**：
  > If you have objects in your loaded collection that require input actions, you need to make sure that
  > the game object that contains the collection proxy acquires input. When the game object receives
  > input messages these are propagated to the components of that object, i.e. the collection proxies.
  > The input actions are sent via the proxy into the loaded collection.

- `https://defold.com/llms/manuals/input.md` → **Input focus**：
  > This message instructs the engine to add input capable components (script components, GUI components
  > and **collection proxies**) in the game objects to the input stack.

- `https://defold.com/llms/manuals/input.md` → **Input focus and collection proxy components**：
  > Each game world that is dynamically loaded through a collection proxy has its own input stack.
  > For action dispatch to reach the loaded world's input stack, the proxy component must be on the
  > main world's input stack. … **It is a common error** to forget to send `acquire_input_focus` to the
  > game object holding the collection proxy component. Skipping this step prevents input from reaching
  > any of the components on the loaded world's input stack.

- 同一手册的补充规则：
  - `All components on a loaded world's stack are handled before dispatch continues down the main stack.`
  - 返回 `true` 消费输入适用于**所有**输入栈；子栈组件可以消费掉、让主栈收不到。

### 第 3 步：论坛（佐证）

- https://forum.defold.com/t/79891/3 「Loading my levels via collection proxy completely messes up
  acquire_input_focus (SOLVED)」：解法正是给持有 proxy 的 GO 发 `msg.post(sender, "acquire_input_focus")`；
  帖内还提到另一个高频错误——上层 `game_manager` 返回 `true` 把输入吃掉，GUI 收不到。
- https://forum.defold.com/t/79632/1 「Trouble with collection proxy」：官方回复原文
  > you did not acquire input focus in your controller.script … The menu and bedroom collections
  > will not be able to acquire input focus since the "parent" (controller.script) has no input focus.
- 官方示例参考：`collection/proxy`、`collection/splash`（https://github.com/defold/examples）。

## 4. 根因（带证据）

`main.collection` 里 `loader` 这个 GO 挂着 `session.script` + `menu_proxy` + `game_proxy`：

```protobuf
embedded_instances {
  id: "loader"
  data: "components {\n  id: \"session\"\n  component: \"/script/session.script\"\n}\n"
  "embedded_components {\n  id: \"menu_proxy\"\n  type: \"collectionproxy\"\n ... "
}
```

v0.4.0 重构后 `session.script` 的 `init` 里**没有** `acquire_input_focus`。
按官方规则，`acquire_input_focus` 才会把 GO 上的 collection proxy 组件加入主输入栈；
proxy 不在主栈 → 子世界的输入栈根本不会被分派 → 子场景里任何脚本再怎么 acquire 都收不到输入。

v0.3 能玩是因为 `world.script` 本身在 `main.collection`（天然就在主栈上），
重构把脚本搬走的同时也把这个隐含前提一起搬走了。

## 5. 修复

`script/session.script` 的 `init` 首行补上（这一步就是官方要求的全部内容）：

```lua
msg.post(".", "acquire_input_focus")
```

`88f7219` 里还额外加了一层中间方案：session 在 `on_input` 里把 action 打包成
`session_input` 消息转发给 `self.menu_url` / `self.world_url`，并 `return true` 消费；
`menu.gui_script`、`script/world.script` 用 `on_message` 的 `session_input` 分支调
`handle_input`（该函数必须声明在 `on_message` **之前**）。切换窗口期
（`pending` / `pending_unload`）不转发，避免 post 到已卸载 socket。

**当前状态**：转发版可跑，但不是官方推荐形态。官方形态是两段式——
loader acquire（让 proxy 入栈）+ 子场景内各脚本自己 acquire，之后交给引擎原生分发，
不需要中间人。转发版的代价：
- 只拷了 `pressed/released/value/x/y`，丢掉 `action.source`、多点触控 touch id、`is_repeat`；
- 子栈本应先于主栈处理，GUI 无法再用「返回 true」表达遮挡优先级；
- 每帧多一次 `msg.post` 与一帧延迟；
- 若子场景脚本同时又 acquire，会**收到两次**输入。

代码注释已在后续更正为官方表述，不再写「引擎丢弃」。

## 6. 验证

- `luac -p script/session.script` 通过。
- **必须 Cmd+B 重新 Build & Run**：已运行的旧实例仍是旧代码，控制台会继续报 `handle_input nil`。
- 验收动作：主页点「开始游戏」进对局；主页点 3 个购买按钮（金币足/不足两种态）；
  结算后返回主页再开局一次。
- 冒烟钩子：`climber.smoke_shop=1`、`climber.smoke_ad=1`。

## 7. 防再犯检查清单

1. 只要有 collection proxy，**先确认持有 proxy 组件的那个 GO 的脚本 init 里有
   `msg.post(".", "acquire_input_focus")`**；不要从子场景脚本里找原因。
2. 若 proxy 与主逻辑挂在不同 GO 上，两者都要 acquire（或统一放到同一个 GO）。
3. 排查「点击无反应」时，先查报错日志里有没有 `attempt to call a nil value`——
   `local function` 声明顺序问题与输入焦点问题症状相同，`luac -p` 查不出来。
4. 检查有没有上游 `on_input` 无条件 `return true` 把输入吃掉（论坛 79891 的第二个坑）。
5. 用 `menu_ready` / `world_ready` 的 `sender` 回包，不手写 proxy 内部对象路径。
6. 下结论前先引用官方手册原句；写「引擎 bug」之前必须能给出可复现的最小工程与官方 issue。

## 8. 关联

- 项目内设计文档：`platformer-game/docs/game-design-v0.4.0.md`（场景结构）
- 项目工作日志：`platformer-game/.workbuddy/memory/2026-11-18.md`
- 官方手册：input.md、collection-proxy.md（见第 3 节 URL）
- 未落地事项：按官方两段式重构输入分发（去掉 session 转发），需重新 Build & Run 验证
