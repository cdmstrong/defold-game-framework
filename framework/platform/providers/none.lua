-- 无广告 provider。
--
-- 用于审核包、纯单机发行、或某些渠道明确不允许广告的情况：
-- 业务代码不需要改，判定永远是「不支持」，所有看广告入口自动隐藏/走替代逻辑。

local M = {}

function M.create(ctx, config)
    local self = { id = "none", ctx = ctx }

    function self:init()
        return true
    end

    function self:is_supported()
        return false
    end

    function self:show_rewarded(show_ctx)
        ctx.log("none_provider", "当前构建未启用广告")
        return { success = false, status = nil, reason = "unsupported" }
    end

    function self:dispose()
        -- noop
    end

    return self
end

return M
