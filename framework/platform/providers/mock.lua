-- 模拟广告 provider —— 只在显式把平台切到 'mock' 时才会用到。
--
-- 设计要点：
-- - 不常驻任何调试页面，只有业务真的调用播放接口时才返回结果。
-- - 选择结果直接映射成和真实 SDK 一样的终态，方便业务分支一次写完。
-- - 纯 Lua 环境（无 DOM）自动降级成「完整观看」：延迟 1s 后返回 rewarded，
--   方便在 Defold HTML5/原生里跑通业务流程。
-- - 可通过 set_chooser 注入自定义结果选择器（调试面板用）。
--
-- V2 两种模式（config.async）：
-- - 同步（默认）：show_rewarded 立即返回终态。HTML5 demo 用，流程一步到位。
-- - 异步（config.async = true）：show_rewarded 返回 { pending = true }，
--   结果经 poll(request_id) 在 resolve_delay_ms（默认 1000ms，按 ctx.now_ms
--   判定）后给出。用于纯 Lua 测试驱动门面的完整轮询/超时链路——
--   与真实渠道（taptap/leyuan）的 V2 契约保持一致。

local M = {}

local RESULT_REWARDED = { success = true, status = 4, reason = "rewarded", mocked = true, raw = { mock = true, status = 4 } }
local RESULT_FAILED = { success = false, status = -1, reason = "failed", mocked = true, raw = { mock = true, status = -1 } }
local RESULT_CLOSED = { success = false, status = 1, reason = "closed", mocked = true, raw = { mock = true, status = 1 } }
local RESULT_SKIPPED = { success = false, status = 2, reason = "skipped", mocked = true, raw = { mock = true, status = 2 } }

local custom_chooser = nil

-- 注入自定义 mock 结果选择器：function(show_ctx) -> result
-- 返回 nil 恢复默认（自动 rewarded）。
function M.set_chooser(chooser)
    custom_chooser = chooser
end

local function choose(show_ctx)
    if not custom_chooser then return RESULT_REWARDED end
    local ok, result = pcall(custom_chooser, show_ctx)
    if not ok then
        return { success = false, status = nil, reason = "exception", mocked = true, error = result }
    end
    if result then
        result.mocked = true
        return result
    end
    return RESULT_REWARDED
end

function M.create(ctx, config)
    config = config or {}
    local self = {
        id = "mock",
        ctx = ctx,
        async = config.async == true,
        resolve_delay_ms = config.resolve_delay_ms or 1000,
        active_request = nil,
        resolve_at = 0,
        resolve_result = nil,
    }

    function self:init()
        return true
    end

    function self:is_supported()
        return true
    end

    function self:show_rewarded(show_ctx)
        ctx.log("mock_show", self.async and "模拟广告（异步 pending）" or "模拟广告结果")

        if not self.async then
            -- 同步模式：立即返回终态（旧契约，HTML5 demo 用）。
            ctx.log("mock_dom_missing", "无交互环境，1s 后自动返回 rewarded")
            ctx.sleep(1.0)
            return choose(show_ctx)
        end

        -- 异步模式：返回 pending，结果延迟后经 poll 给出。
        self.active_request = show_ctx.request_id
        self.resolve_at = ctx.now_ms() + self.resolve_delay_ms
        self.resolve_result = choose(show_ctx)
        return { pending = true, mocked = true }
    end

    -- 异步模式轮询。nil = 未到时间；result = 终态。
    function self:poll(request_id)
        if not self.async then return nil end
        if self.active_request ~= request_id then return nil end
        if ctx.now_ms() < self.resolve_at then return nil end
        self.active_request = nil
        ctx.log("mock_settled", tostring(self.resolve_result.reason))
        return self.resolve_result
    end

    function self:dispose()
        self.active_request = nil
    end

    return self
end

return M
