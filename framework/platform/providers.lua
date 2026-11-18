-- provider 注册表。
--
-- 接新渠道只需要两步，不用改 service 和业务代码：
-- 1. 新建 providers/Xxx.lua 实现 provider 契约；
-- 2. 在本文件 register_provider('xxx', factory) 注册。
--
-- 然后在 config 里把 ad_platform 改成 'xxx' 即可打包。

local M = {}

local taptap = require "framework.platform.providers.taptap"
local leyuan = require "framework.platform.providers.leyuan"
local mock = require "framework.platform.providers.mock"
local none = require "framework.platform.providers.none"

-- id -> factory(ctx, config) -> provider
local factories = {
    taptap = function(ctx, config) return taptap.create(ctx, config) end,
    leyuan = function(ctx, config) return leyuan.create(ctx, config) end,
    mock = function(ctx, config) return mock.create(ctx, config) end,
    none = function(ctx, config) return none.create(ctx, config) end,
}

function M.register_provider(id, factory)
    assert(type(id) == "string" and type(factory) == "function", "id and factory required")
    factories[id] = factory
end

function M.has_provider(id)
    return factories[id] ~= nil
end

-- 未知平台一律回落到 none，避免线上崩在广告入口。
function M.create_provider(id, ctx, config)
    local factory = factories[id] or factories.none
    return factory(ctx, config)
end

return M
