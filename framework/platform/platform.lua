-- 平台检测抽象。
--
-- 目标：业务侧只问「当前在浏览器 / 桌面 / 移动」，不问具体引擎 API。
-- 通过注入 sys（Defold 的 sys 模块）来判断，纯 Lua 下可注入 stub 测试。
--
-- detect() -> { kind = "browser"|"desktop"|"mobile"|"unknown", system_name = string }

local M = {}

local DESKTOP_NAMES = { Darwin = true, Windows = true, Linux = true }
local MOBILE_NAMES = { Android = true, ["iPhone OS"] = true }
-- Defold HTML5 构建的 system_name（旧版引擎用 Emscripten）。
local BROWSER_NAMES = { HTML5 = true, Emscripten = true }

function M.create(options)
    options = options or {}
    local self = {
        sys = options.sys, -- Defold sys module（可注入）
        override = options.override, -- 可注入覆盖，用于测试/多渠道同包
    }

    function self:detect()
        if self.override and type(self.override) == "table" and self.override.kind then
            return self.override
        end

        local sys = self.sys
        local system_name = "unknown"
        if sys and sys.get_sys_info then
            local ok, info = pcall(function() return sys.get_sys_info() end)
            if ok and type(info) == "table" and type(info.system_name) == "string" then
                system_name = info.system_name
            end
        end

        if BROWSER_NAMES[system_name] then
            return { kind = "browser", system_name = system_name }
        end
        if DESKTOP_NAMES[system_name] then
            return { kind = "desktop", system_name = system_name }
        end
        if MOBILE_NAMES[system_name] then
            return { kind = "mobile", system_name = system_name }
        end
        return { kind = "unknown", system_name = system_name }
    end

    function self:is_browser()
        return self:detect().kind == "browser"
    end

    function self:is_desktop()
        return self:detect().kind == "desktop"
    end

    function self:is_mobile()
        return self:detect().kind == "mobile"
    end

    return self
end

return M
