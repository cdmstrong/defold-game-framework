-- 模拟广告 provider —— 只在显式把平台切到 'mock' 时才会用到。
--
-- 设计要点：
-- - 不常驻任何调试页面，只有业务真的调用播放接口时才返回结果。
-- - 选择结果直接映射成和真实 SDK 一样的终态，方便业务分支一次写完。
-- - 纯 Lua 环境（无 DOM）自动降级成「完整观看」：延迟 1s 后返回 rewarded，
--   方便在 Defold HTML5/原生里跑通业务流程。
-- - 可通过 set_chooser 注入自定义结果选择器（调试面板用）。

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

function M.create(ctx, config)
    local self = { id = "mock", ctx = ctx }

    function self:init()
        return true
    end

    function self:is_supported()
        return true
    end

    function self:show_rewarded(show_ctx)
        ctx.log("mock_show", "模拟广告结果")

        if custom_chooser then
            local ok, result = pcall(custom_chooser, show_ctx)
            if not ok then
                return { success = false, status = nil, reason = "exception", mocked = true, error = result }
            end
            if result then
                result.mocked = true
                return result
            end
        end

        -- 无自定义选择器：延迟 1s 模拟观看，返回 rewarded。
        ctx.log("mock_dom_missing", "无交互环境，1s 后自动返回 rewarded")
        ctx.sleep(1.0)
        return RESULT_REWARDED
    end

    function self:dispose()
        -- noop
    end

    return self
end

return M
