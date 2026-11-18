-- 广告平台 provider 接口约定（Lua 版，V2：异步轮询契约）。
--
-- 约定（对齐 cocos-template 的 IAdProvider.ts）：
-- - provider 只负责「把某个平台的 SDK 差异抹平」，不做重试、不做幂等、不做业务发奖。
-- - provider 必须把过程中的中间态（展示成功 / 点击）自己消化掉，只在终态时结算。
-- - is_supported 返回 false 时，上层不会调用 show_rewarded。
--
-- V2 契约（关键变更：show_rewarded 不再阻塞等待终态）：
--   真实渠道的激励视频从 show() 到 onClose 间隔数秒到数十秒，而 js 执行器
--   （html5.run）是同步的。阻塞式 provider 会在广告刚开始时就「读到无结果」
--   而提前返回失败、恢复游戏，且晚到的 JS 回调结果会污染下一次请求。
--   因此 provider 必须实现异步轮询契约：
--
--   show_rewarded(show_ctx)
--     -> { pending = true }              -- 已发起，结果稍后经 poll 获取
--     | result                           -- 同步终态（仅 mock/none 等瞬时渠道）
--   poll(request_id)
--     -> nil                             -- 广告未结束，继续等
--     | result                           -- 终态：{ success, status, reason, raw, error }
--
--   request_id 贯穿 show → poll：JS 侧结果必须携带发起时的 request_id；
--   poll 只消费匹配当前请求的结果，不匹配的（晚到的旧结果）必须丢弃并清理，
--   绝不返回——否则会污染下一次请求。
--
--   init/is_supported 里的 SDK 加载同样是异步的（script onload）：
--   init() 未就绪时返回 false（不算 error），is_supported 未就绪时返回 false
--   且不缓存 false（可能是暂时的加载中）。SDK 就绪后 is_supported 自然变 true。
--
-- 每个 provider 是 create(ctx, config) 返回的表，ctx 由门面注入：
--   ctx.js(code)   -- 执行一段 JavaScript（Defold HTML5 用 html5.run；原生/纯 Lua 无）
--   ctx.log(event, detail, raw)  -- 统一日志出口
--   ctx.now_ms()   -- 墙钟毫秒（用于超时）
--   ctx.sleep(sec) -- mock 专用；真实渠道禁用
--
-- provider 必须实现：
--   init()             -> true | nil, error（未就绪返回 false 不算 error）
--   is_supported()     -> bool
--   show_rewarded(show_ctx) -> { pending = true } | result
--   poll(request_id)   -> nil | result
--   dispose()          -> nil (可选)
--
-- JS 结果协议（真实渠道统一）：
--   发起时：window.__ad_result__ = null; window.__ad_active__ = "<request_id>"
--   终态时：window.__ad_result__ = { request_id, ok, reason, status, raw, error }
--   轮询时：request_id 匹配 → 返回并清空；不匹配 → 视为 stale，清空丢弃。

local M = {}

M.IDS = { TAPTAP = "taptap", LEYUAN = "leyuan", MOCK = "mock", NONE = "none" }

return M
