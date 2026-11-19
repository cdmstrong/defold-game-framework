-- 激励视频门面（业务唯一入口，V2：异步轮询契约）。
--
-- 业务侧关心三件事：能不能看、发起播放、结果结算。
-- 平台差异、多次回调、超时、重入、幂等都在这一层和 provider 层消化掉。
--
-- V2 用法（真实渠道是异步的，必须接 update 轮询）：
--   local reward = RewardAd.create({ platform = "taptap", ... })
--   reward:on_ad_open(function() pause:acquire("ad") end)
--   reward:on_ad_close(function(result) pause:release(); handle(result) end)
--
--   -- 点击时：
--   local result = reward:show_rewarded({ tag = "revive" })
--   if not result.pending then handle(result) end   -- 同步终态（busy/mock）
--
--   -- 每帧（如 Defold update）：
--   local settled = reward:update()
--   -- settled ~= nil 时 on_ad_close 已触发，无需重复处理
--
--   -- 发奖（幂等）：
--   if result.success then reward:grant_once(result.request_id, function() ... end) end
--
-- 时序语义：
--   show_rewarded 立即返回；真实渠道返回 { pending = true }（busy 保持 true，
--   on_ad_open 已触发），终态由 update() 轮询 provider:poll(request_id) 获得。
--   update() 同时是看门狗：pending 超过 timeout_ms + grace 时兜底结算为
--   timeout 并释放 busy，杜绝「广告卡死导致游戏永久暂停」。
--   request_id 贯穿 show → poll，provider 丢弃 request_id 不匹配的晚到结果，
--   因此上一个请求的迟到结果绝不会污染或冒充下一次请求。
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
        -- html5.run(code) 执行 JS 并返回字符串结果（provider 的 JS 负责把
        -- 状态 JSON.stringify 回来；发起类语句返回 undefined → nil）。
        local ok, res = pcall(run, code)
        if not ok then return nil end
        return res
    end
end

function M.create(options)
    options = options or {}
    local sys = options.sys

    local self = {
        platform_id = options.platform or "none",
        config = options.config or {}, -- per-provider 配置（ad_unit_id / sdk_url / async 等）
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
        sleep = options.sleep or function(sec) end, -- mock 同步模式用；默认 no-op
        pending_request = nil, -- { request_id, started_at, timeout_at, provider }
    }

    -- provider 上下文
    local ctx = {
        js = function(code)
            return self.js(code)
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

    -- 终态归一化 + busy 释放 + close 事件。唯一的结算出口。
    local function settle(result, provider_result)
        provider_result = provider_result or {}
        result = result or {}
        result.success = provider_result.success == true
        result.status = provider_result.status
        result.reason = provider_result.reason or "unknown"
        result.platform = result.platform or self.platform_id
        result.request_id = result.request_id
        result.mocked = provider_result.mocked == true
        result.duration_ms = self.now_ms() - (result.started_at or self.now_ms())
        result.raw = provider_result.raw
        result.error = provider_result.error
        result.events = provider_result.events

        self.busy = false
        self.busy_tag = ""
        self.pending_request = nil

        self.logger:log("show_end", tostring(result.reason) .. " success=" .. tostring(result.success) .. " " .. tostring(result.duration_ms) .. "ms", result.raw)
        emit_close(result)
        return result
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

    -- 预热：提前加载 SDK。返回 SDK 是否就绪（未就绪不算失败，稍后自然就绪）。
    function self:init()
        local provider = get_provider()
        local ok, err = provider:init()
        if ok == nil then
            self.logger:warn("init_failed", tostring(err and err.message or err))
            return false
        end
        if provider.poll_init then
            return provider:poll_init() and true or false
        end
        return ok and true or false
    end

    -- 是否可播放激励视频。false 时业务应隐藏入口或走替代逻辑。
    -- false 不区分「渠道不可用」与「SDK 还在加载」——后者稍后自然变 true。
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

    -- 发起播放。
    -- 返回值：
    --   { pending = true, request_id, platform, started_at }  -- 异步进行中，
    --       busy 保持 true，结果等 update() 轮询；result.success 为 nil
    --   result（完整归一化结果）                                -- 同步终态
    --   busy / 异常路径返回 success=false 的完整结果（非 pending）
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

        local ok, provider_result = pcall(function()
            local provider = get_provider()
            return provider:show_rewarded({
                request_id = request_id,
                timeout_ms = timeout_ms + self.watchdog_grace_ms,
                tag = show_options.tag,
            })
        end)

        if not ok then
            -- provider 抛异常：立即结算为 exception（非 pending）。
            return settle({
                started_at = started_at,
                request_id = request_id,
            }, { success = false, reason = "exception", error = provider_result })
        end

        if type(provider_result) == "table" and provider_result.pending then
            -- 异步进行中：保持 busy，记录看门狗截止时间，等 update() 轮询。
            self.pending_request = {
                request_id = request_id,
                started_at = started_at,
                timeout_at = started_at + timeout_ms + self.watchdog_grace_ms,
                provider = get_provider(),
            }
            self.logger:log("show_pending", "request_id=" .. tostring(request_id) .. " 等待 update() 轮询终态")
            return {
                pending = true,
                request_id = request_id,
                platform = platform,
                started_at = started_at,
            }
        end

        -- 同步终态（mock/none/busy 等）：立即结算。
        return settle({ started_at = started_at, request_id = request_id }, provider_result)
    end

    -- 每帧轮询 pending 广告。返回 nil（进行中）或结算后的完整结果
    -- （结算时 on_ad_close 已触发；结果.reason 可能是 timeout —— 看门狗兜底）。
    function self:update()
        local pending = self.pending_request
        if not pending then return nil end
        local now = self.now_ms()

        -- 看门狗：provider 一直没给终态（JS 回调丢失/宿主异常），兜底结算，
        -- 释放 busy 与暂停，避免游戏永久卡在广告态。
        if now > pending.timeout_at then
            self.logger:warn("watchdog", "request_id=" .. tostring(pending.request_id) .. " 超时未收到终态，兜底结算")
            return settle({
                started_at = pending.started_at,
                request_id = pending.request_id,
            }, { success = false, reason = "timeout", status = nil })
        end

        local ok, polled = pcall(pending.provider.poll, pending.provider, pending.request_id)
        if not ok then
            self.logger:error("poll_error", tostring(polled))
            return settle({
                started_at = pending.started_at,
                request_id = pending.request_id,
            }, { success = false, reason = "exception", error = polled })
        end
        if polled == nil then return nil end

        return settle({
            started_at = pending.started_at,
            request_id = pending.request_id,
        }, polled)
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
