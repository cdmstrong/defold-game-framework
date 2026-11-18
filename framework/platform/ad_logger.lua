-- 广告模块日志：控制台输出 + 内存环形缓冲（供诊断面板读取）。
-- 不依赖引擎与 DOM，小游戏 / 原生环境同样可用。纯 Lua。
--
-- 对齐 cocos-template 的 AdLogger.ts 语义。

local M = {}

local MAX_ENTRIES = 80

-- 防止把整个 SDK 对象塞进日志缓冲区（浅拷贝 + 不可序列化时降级为字符串）。
local function safe_snapshot(value)
    if value == nil then return nil end
    local t = type(value)
    if t ~= "table" then return value end
    local ok, copy = pcall(function()
        local out = {}
        for k, v in pairs(value) do
            if type(v) == "table" then out[k] = tostring(v)
            else out[k] = v end
        end
        return out
    end)
    if ok then return copy end
    return tostring(value)
end

function M.create(options)
    options = options or {}
    local self = {
        entries = {},
        verbose = options.verbose ~= false,
        out = options.out or print,
    }

    local function push(level, event, detail, raw)
        local entry = {
            time = os.date("%H:%M:%S"),
            level = level,
            event = event,
            detail = detail,
            raw = raw ~= nil and safe_snapshot(raw) or nil,
        }
        table.insert(self.entries, 1, entry)
        if #self.entries > MAX_ENTRIES then
            self.entries[#self.entries] = nil
        end
        if not self.verbose then return end
        self.out("[Ad:" .. event .. "] " .. detail)
    end

    function self:set_verbose(verbose)
        self.verbose = not not verbose
    end

    function self:is_verbose()
        return self.verbose
    end

    function self:log(event, detail, raw)
        push("log", event, detail, raw)
    end

    function self:warn(event, detail, raw)
        push("warn", event, detail, raw)
    end

    function self:error(event, detail, raw)
        push("error", event, detail, raw)
    end

    function self:get_entries()
        local out = {}
        for i, e in ipairs(self.entries) do out[i] = e end
        return out
    end

    function self:clear()
        self.entries = {}
    end

    return self
end

return M
