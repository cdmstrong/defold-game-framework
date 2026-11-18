-- 广告平台 provider 接口约定（Lua 版）。
--
-- 约定（对齐 cocos-template 的 IAdProvider.ts）：
-- - provider 只负责「把某个平台的 SDK 差异抹平」，不做重试、不做幂等、不做业务发奖。
-- - provider 必须把过程中的中间态（展示成功 / 点击）自己消化掉，
--   只在终态的时候 resolve，否则上层无法区分「还没完」和「失败」。
-- - is_supported 返回 false 时，上层不会调用 show_rewarded。
--
-- 每个 provider 是 create(ctx, config) 返回的表，ctx 由门面注入：
--   ctx.js(code)   -- 执行一段 JavaScript（Defold HTML5 用 html5.run；原生/纯 Lua 无）
--   ctx.log(event, detail, raw)  -- 统一日志出口
--   ctx.now_ms()   -- 墙钟毫秒（用于超时）
--
-- provider 必须实现：
--   init()            -> true | nil, error
--   is_supported()    -> bool
--   show_rewarded(show_ctx) -> result   -- 阻塞式（在协程/回调里驱动）
--   dispose()         -> nil (可选)
--
-- 因为 Lua 没有 Promise，激励视频的「异步 + 多次回调 + 终态才结算」语义用
-- 注入的 js 执行器 + 回调桥接实现；纯 Lua 测试用假 js 执行器驱动状态机。

local M = {}

M.IDS = { TAPTAP = "taptap", LEYUAN = "leyuan", MOCK = "mock", NONE = "none" }

return M
