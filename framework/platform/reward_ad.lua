-- 激励视频门面（业务唯一入口）。
--
-- 业务侧只关心两件事：能不能看、看完发不发奖。
-- 平台差异、多次回调、超时、重入、幂等都在这一层和 provider 层消化掉。
--
-- 用法：
--   local reward = RewardAd.create({ platform = "leyuan", js = js_exec, ... })
--   local result = reward:show_rewarded({ tag = "revive" })
--   if result.success then reward:grant_once(result.request_id, function() grant_reward() end) end
--
-- 广告播放期间游戏主循环要暂停，用 on_ad_open / on_ad_close：
--   reward:on_ad_open(function() ... end)
--   reward:on_ad_close(function(result) ... end)
--
-- 对齐 cocos-template 的 RewardAdService.ts 语义。

local Types = require "framework.platform.ad_types"
local Providers = require "framework.platform.providers"
local AdLogger = require "framework.platform.ad_logger"

local M = {}

local SUPPORT_FALSE_TTL_MS = 30000
local MAX_GRANTED_ID = 200

local function default_now_ms()
    return math.floor(os.time() * 1000)
end

-- 注入的 js 执行器：默认用 Defold 的 html5.run（HTML5 构建，全局函数）。
-- 桌面/原生或纯 Lua 环境无 html5，此时返回 nil（provider 判为 unsupported）。
local function default_js_exec()
    return nil
end

-- 从注入的 sys 构建 js 执行器。Defold HTML5 下 html5.run 是全局函数（非 sys.html5），
-- 由调用方传入 html5 引用；这里通过 options.html5 或 sys 尽力探测。
local function build_js_exec(sys, html5_mod, json)
    local run = html5_mod and html5_mod.run
    if not run and sys and sys.html5 and sys.html5.run then run = sys.html5.run end
    if not run and _G and type(_G.html5) == "table" and _G.html5.run then run = _G.html5.run end
    if not run then return nil end

    return function(code)
        -- html5.run(code) 执行 JS；结果通过 window.__ad_result__ 回传。
        -- 再用一次 html5.run 读取 JSON 字符串。
        local ok, _ = pcall(run, code)
        if not ok then return nil end
        local read = run("window.__ad_result__ ? JSON.stringify(window.__ad_result__) : ''")
        if type(read) == "string" and read ~= "" then
            local decoded = nil
            if json and json.decode then decoded = json.decode(read) end
            if not decoded then
                local ok2, d = pcall(function() return _G.json and _G.json.decode(read) end)
                if ok2 then decoded = d end
            end
            -- 清理，避免跨调用污染
            pcall(run, "window.__ad_result__ = undefined")
            return decoded
        end
        return nil
    end
end

function M.create(options)
    options = options or {}
    local sys = options.sys

    local self = {
        platform_id = options.platform or "none",
        config = options.config or {}, -- per-provider 配置（ad_unit_id / sdk_url 等）
        js = options.js or build_js_exec(sys, options.html5) or default_js_exec,
        logger = options.logger or AdLogger.create({ out = options.out }),
        provider = nil,
        support_cache = nil,
        support_cache_at = 0,
        busy = false,
        busy_tag = "",
        counter = 0,
        granted_ids = {},
        open_listeners = {},
        close_listeners = {},
        timeout_ms = options.timeout_ms or 120000,
        watchdog_grace_ms = options.watchdog_grace_ms or 15000,
        now_ms = options.now_ms or default_now_ms,
        sleep = options.sleep or function(sec) end, -- mock provider 用；默认 no-op
    }

    -- provider 上下文
    local ctx = {
        js = function(code)
            local res = self.js(code)
            return res
        end,
        log = function(event, detail, raw) self.logger:log(event, detail, raw) end,
        now_ms = function() return self.now_ms() end,
        sleep = function(sec) if self.sleep then self.sleep(sec) end end,
        decode_json = options.decode_json, -- 可选注入（非 HTML5 用 json.decode）
    }

    local function get_provider()
        if not self.provider then
            self.provider = Providers.create_provider(self.platform_id, ctx, self.config)
            self.logger:log("provider_created", "platform=" .. tostring(self.platform_id))
        end
        return self.provider
    end

    local function emit_open()
        for _, fn in ipairs(self.open_listeners) do
            local ok, err = pcall(fn)
            if not ok then self.logger:error("open_listener_error", tostring(err)) end
        end
    end

    local function emit_close(result)
        for _, fn in ipairs(self.close_listeners) do
            local ok, err = pcall(fn, result)
            if not ok then self.logger:error("close_listener_error", tostring(err)) end
        end
    end

    local function create_request_id()
        self.counter = (self.counter + 1) % 100000
        return tostring(self.platform_id) .. "-" .. tostring(self.now_ms()) .. "-" .. tostring(self.counter)
    end

    -- 平台 id
    function self:get_platform_id()
        return self.platform_id
    end

    function self:set_platform(id)
        if self.busy then
            self.logger:warn("platform_set_ignored", "广告播放中，忽略切换平台")
            return
        end
        if self.provider and self.provider.dispose then
            pcall(self.provider.dispose)
        end
        self.provider = nil
        self.platform_id = id
        self.support_cache = nil
        self.support_cache_at = 0
        self.logger:log("platform_set", "platform=" .. tostring(id))
    end

    -- 预热：提前加载 SDK。返回 SDK 是否就绪。
    function self:init()
        local ok, err = get_provider():init()
        if not ok then
            self.logger:warn("init_failed", tostring(err and err.message or err))
            return false
        end
        return true
    end

    -- 是否可播放激励视频。false 时业务应隐藏入口或走替代逻辑。
    function self:is_supported()
        if self.support_cache == true then return true end
        if self.support_cache == false and (self.now_ms() - self.support_cache_at) < SUPPORT_FALSE_TTL_MS then
            return false
        end
        local ok, supported = pcall(function() return get_provider():is_supported() end)
        if not ok then
            self.logger:error("support_error", tostring(supported))
            return false
        end
        self.support_cache = supported and true or false
        self.support_cache_at = self.now_ms()
        return supported and true or false
    end

    function self:is_busy()
        return self.busy
    end

    -- 播放激励视频。返回归一化的 RewardedVideoResult。
    function self:show_rewarded(show_options)
        show_options = show_options or {}
        local started_at = self.now_ms()
        local platform = self.platform_id
        local request_id = create_request_id()
        local timeout_ms = show_options.timeout_ms or self.timeout_ms

        if self.busy then
            self.logger:warn("busy", "上一次广告未结束，忽略本次调用 tag=" .. tostring(show_options.tag or self.busy_tag))
            return {
                success = false, status = nil, reason = "busy", platform = platform,
                request_id = request_id, mocked = false, duration_ms = 0,
            }
        end

        self.busy = true
        self.busy_tag = show_options.tag or ""
        emit_open()
        self.logger:log("show_begin", "platform=" .. platform .. " tag=" .. tostring(show_options.tag or "-") .. " timeout=" .. tostring(timeout_ms))

        local result
        local ok, provider_result = pcall(function()
            local provider = get_provider()
            -- 看门狗：provider 自身会超时，但万一卡住，这里兜底结算。
            -- 由于 Lua 无 Promise，watchdog 依赖 provider 内部遵守 timeout_ms；
            -- 门面侧不再二次计时（避免纯 Lua 测试复杂化），但仍保留兜底语义。
            return provider:show_rewarded({
                request_id = request_id,
                timeout_ms = timeout_ms + self.watchdog_grace_ms,
                tag = show_options.tag,
            })
        end)

        if not ok then
            result = {
                success = false, status = nil, reason = "exception", platform = platform,
                request_id = request_id, mocked = false,
                duration_ms = self.now_ms() - started_at, error = provider_result,
            }
        else
            provider_result = provider_result or {}
            result = {
                success = provider_result.success == true,
                status = provider_result.status,
                reason = provider_result.reason or "unknown",
                platform = platform,
                request_id = request_id,
                mocked = provider_result.mocked == true,
                duration_ms = self.now_ms() - started_at,
                raw = provider_result.raw,
                error = provider_result.error,
            }
        end

        self.busy = false
        self.busy_tag = ""

        self.logger:log("show_end", tostring(result.reason) .. " success=" .. tostring(result.success) .. " " .. tostring(result.duration_ms) .. "ms", result.raw)
        emit_close(result)
        return result
    end

    -- 同一次广告只发一次奖。
    -- 返回真正执行了发奖返回 true，重复调用返回 false。
    function self:grant_once(request_id, grant)
        if not request_id or request_id == "" then
            self.logger:warn("grant_invalid", "request_id 为空，拒绝发奖")
            return false
        end
        for _, id in ipairs(self.granted_ids) do
            if id == request_id then
                self.logger:warn("grant_dup", "request_id=" .. tostring(request_id) .. " 已发过奖，忽略")
                return false
            end
        end

        table.insert(self.granted_ids, request_id)
        if #self.granted_ids > MAX_GRANTED_ID then
            table.remove(self.granted_ids, 1)
        end

        local ok, err = pcall(grant)
        if not ok then
            -- 发奖过程中抛错，撤销记录，允许下一次重试
            for i = #self.granted_ids, 1, -1 do
                if self.granted_ids[i] == request_id then table.remove(self.granted_ids, i) end
            end
            self.logger:error("grant_error", "request_id=" .. tostring(request_id) .. " 发奖异常", err)
            error(err, 0)
        end
        self.logger:log("grant_ok", "request_id=" .. tostring(request_id))
        return true
    end

    function self:was_granted(request_id)
        for _, id in ipairs(self.granted_ids) do
            if id == request_id then return true end
        end
        return false
    end

    -- 生命周期事件
    function self:on_ad_open(listener)
        table.insert(self.open_listeners, listener)
        return function()
            for i = #self.open_listeners, 1, -1 do
                if self.open_listeners[i] == listener then table.remove(self.open_listeners, i) end
            end
        end
    end

    function self:on_ad_close(listener)
        table.insert(self.close_listeners, listener)
        return function()
            for i = #self.close_listeners, 1, -1 do
                if self.close_listeners[i] == listener then table.remove(self.close_listeners, i) end
            end
        end
    end

    -- 诊断日志
    function self:get_diagnostics()
        return self.logger:get_entries()
    end

    return self
end

return M
