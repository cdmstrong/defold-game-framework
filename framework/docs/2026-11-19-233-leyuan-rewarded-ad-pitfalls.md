# 233 乐园（MetaH5Ad）激励视频：看完没奖励的六层坑与最终根因

- 日期：2026-11-19
- 项目：Sky Climber / 无极天宫（platformer-game），233 乐园 H5 渠道
- 关键词：233乐园、MetaH5Ad、激励视频、html5.run、JS 模板替换、IIFE 双重调用、异步轮询、settle、status=4、看完没奖励、busy、回调异常、logBlue、JSON.stringify 循环引用
- 适用版本：Defold 1.14.1（wasm-web）；MetaH5Ad `https://cdn.233xyx.com/h5ad/metah5ad_v1.min.js`

## 现象与复现

真机（233 App 内 WebView）完整复现路径：进游戏 → 死亡 → 点「复活看广告」→
广告正常播放完 → 关闭广告 → **游戏没有复活、没有奖励，一直显示「加载广告中」；
再点广告按钮无响应**（第二次起被 busy 挡掉，感知为「广告只有第一次能看」）。
纯 JS 的独立测试页（`ad_test.html`）在**同一台真机**上却能完整走通
`st0 → st3 → st4 → st1` 并拿到奖励——游戏与测试页行为不一致是本案最大的迷惑点。

复现条件：Defold HTML5 构建 + `html5.run` 注入的 provider JS + 真实 SDK 回调链路。
桌面浏览器（WebGL swiftshader 起不来）与 headless Chrome 均无法复现，真机为必经路径。

## 错误假设（走过的弯路，别删）

1. ❌「域名白名单没配」——测试页在同一域名下拿到了 st4，排除。
2. ❌「233 容器不发恢复事件 / 引擎主循环冻结」——DOM 心跳 + LUA 心跳证明页面 JS
   与引擎 Lua 在广告关闭后都活着（`LUA⏱ +0s`），排除。pause 服务也确认不影响
   `app:update`（`app.lua` 不读 pause 状态），排除「暂停死锁」。
3. ❌「SDK 没回调」——overlay 捕获到 SDK 自己的 console 日志
   `给广告方的回调结果 {..."status":4...}`，回调确实到了。
4. ❌「异常兜底写法」——v11 在 catch 里「异常 → 立即结算失败」反而把第一次回调
   （st0 过程态）的异常锁死成失败终态，st4 的奖励兜底永远没机会。**过程态异常
   绝不能锁定终态**。
5. ❌「JSON.stringify 循环引用是根因」——它是真实的异常源之一，但修掉后回调照样
   全抛错；真凶另有其人（见根因）。

## 三步查证结果

1. 框架 docs：无 233 相关沉淀（本文是第一篇）。
2. 官方文档：233 MetaH5Ad 无公开文档可查；以 233 官方 Cocos 模板
   （`LeyuanAdProvider.ts` / `RewardAdService.ts` / `installGlobalLogFallback`）
   为唯一权威参照。
3. 论坛/社区：无公开案例。最终靠 **Node vm 复现脚本**（见验证）钉死根因——
   这一步比任何外部资料都有效，是本案的破案方法论。

## 根因（带日志证据）

按时间顺序共有六层坑，前五个都会独立造成「看完没奖励」，第六个是贯穿始终的真凶：

1. **SDK 依赖全局日志函数**：MetaH5Ad 内部调用 `logBlue/logGreen/logRed/logYellow`，
   缺失时 ReferenceError 打断回调。→ 注入 SDK script 前先补齐（只补缺失）。
2. **SDK 半就绪**：`window.MetaH5Ad` 已挂载但方法未初始化。→ 就绪判定要求
   `showAd` 与 `isAdSupport` 均为 function。
3. **回调多次触发 + 晚到事件覆盖**：一次播放回调序列 `0→3→4→1`，status=1（关闭）
   晚于 status=4（奖励）到达，按「最后一次回调」结算会吃掉奖励。→ settle 一次性锁定。
4. **JS 弱等号陷阱**：归一化里 `v===''` 判空串，`0 === ''` 为 true →
   `toNum(0)` 把 status/code=0 归一成 null。→ `(typeof v === 'string' && v === '')`。
5. **回调异常静默吞事件**：链路中任何未捕获异常（stringify 循环引用、getter 抛错、
   下述第 6 条的 TypeError）都打断 settle，WebView 无提示。→ 回调整体 try/catch +
   过程态异常不锁终态 + raw 含 `status:4` 时兜底发奖。
6. **⭐ JS 模板替换产生双重调用 IIFE（最终根因）**：归一化模板被写成自执行 IIFE
   `(function(raw){...})(raw)`，而调用点是 `var p = __NORMALIZE__(raw)`。gsub 替换后：

   ```js
   var p = (function(raw){...})(raw)(raw);
   //      └── IIFE ──┘└─┘  ← IIFE 返回的结果对象又被当函数调用 → TypeError
   ```

   **SDK 的每一次回调都在归一化这行抛 `TypeError: ... is not a function`**，
   settle 全部被打断。证据链：真机截图 `ERR TypeError: 0 (function(raw)...` →
   overlay ADERR 行亮出完整消息 → Node vm 复现脚本报
   `TypeError: (intermediate value)×N(...) is not a function`，堆栈指向最终 JS
   第 33 行的 `})(raw)\n(raw);`。V8 对该错误的消息渲染会把整段调用链表达式
   （WebView 上表现为函数源码）塞进 message，极具迷惑性。

**真机与测试页不一致的原因**：游戏侧 showAd 回调经 `html5.run` 注入 eval 执行、
归一化走模板替换；测试页是手写普通函数调用，形状正确。

## 修复（全部落在 `framework/platform/providers/leyuan.lua`）

1. 注入 SDK 前补 `logBlue/logGreen/logRed/logYellow`（只补缺失，不覆盖）。
2. 就绪判定：`typeof s.showAd === 'function' && typeof s.isAdSupport === 'function'`。
3. settle 一次性锁定；过程态（0/3）继续等；status=4 立即锁定成功；status=1/2/-1
   结算失败；未知状态交给超时兜底（看门狗 120s + 15s grace）。
4. `toNum` 修弱等号。
5. 回调三层异常防御：
   - 回调整体 try/catch，异常强制 settle（`callback_exception`，error 带堆栈）；
   - **过程态异常不锁终态**（只记 `window.__ad_error__`，等后续回调或超时）；
   - 异常兜底时 `safeStr(raw)` 含 `status:4` 仍按奖励结算（`rewarded_fallback`）。
6. **归一化模板改纯函数表达式**：`local NORMALIZE_JS = [[ function(raw) {...} ]]`，
   `NORMALIZE_INJECTED = "(" .. NORMALIZE_JS .. ")"`，调用点保持 `__NORMALIZE__(raw)`。
7. 所有 `JSON.stringify` 走 `safeStr`（双层 try，循环引用/undefined 不炸）。
8. 架构契约不变：一切 SDK 交互「发起 + 轮询」，终态 JS 写 `window.__ad_result__`
   （带 request_id），Lua 每帧 poll 消费，stale 丢弃；provider 层丢 request_id
   不匹配的晚到结果。

## 验证（真实复现 + 回归）

- `scripts/repro_ad_callback.js`（platformer-game 仓库）：Node vm 从 leyuan.lua
  提取模板 → 按 make_js 顺序替换 → mock SDK 依次回调 st0/3/4/1，覆盖普通对象 /
  JSON 字符串 / 循环引用 / 原始值 / getter 抛错形态。修复前全部抛错；修复后全部
  正确 settle（rewarded st4 或正常 close）。
- 真机（233 App）：看广告 → 复活成功，金币翻倍/补充正常，可反复观看，busy 消失。

## 防再犯检查清单

- [ ] 改任何 `html5.run` 注入的 JS 模板后，**必须跑 Node vm 复现脚本做最终产物断言**——
      gsub 拼接链的形状错误（双调用、漏替换、`%` 魔法字符）静析查不出来。
- [ ] Lua 里嵌入 JS 长字符串用 `[==[ ]==]`，防 `]]` 提前闭合（`window[names[i]]` 类代码）。
- [ ] SDK 回调一律整体 try/catch；**过程态异常不锁终态**；奖励兜底看 raw 原文。
- [ ] settle 只允许一条路径、一次性锁定；看门狗兜底必须保留。
- [ ] JS 数值归一化禁用裸 `==`（`0===''` 为 true）；判空用 `typeof v === 'string'`。
- [ ] 真机排障工具链常备：DOM 心跳 overlay（`DIAG=1` 注入，含 JS/LUA 心跳、AD-ev
      回调序列、ADERR 固定行、console 镜像）+ 独立 SDK 测试页 + URL 参数冒烟开关。
- [ ] 先用纯 JS 测试页证明「SDK 环境通」，再怀疑引擎桥接层——两者的差异点就是
      模板注入路径。

## 关联 commit

- game-framework master `10a1dd9`：NORMALIZE 双重调用根因修复 + safeStr 加固
- game-framework master `2af2bd2`：过程态异常不锁终态
- game-framework master `009dce1`：回调异常强制 settle + rewarded_fallback
- game-framework master `066eb7b`：logBlue 系全局日志函数兜底
- platformer-game `145d009` / `54ee03f`：依赖升级、诊断 overlay、release 包
- 复现脚本：platformer-game `scripts/repro_ad_callback.js`
