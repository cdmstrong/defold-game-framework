-- Platform + Ads + Analytics tests (pure Lua, V2 async poll contract).
package.path = "./?.lua;./?/init.lua;../?.lua;../?/init.lua;" .. package.path

local T = require "tests.lua.harness"
local Types = require "framework.platform.ad_types"
local Platform = require "framework.platform.platform"
local Analytics = require "framework.analytics.analytics"
local Providers = require "framework.platform.providers"
local RewardAd = require "framework.platform.reward_ad"

-- Types ----------------------------------------------------------------------
T.run("ad_types constants", function()
    T.assert_eq(Types.AD_STATUS.REWARDED, 4)
    T.assert_eq(Types.AD_STATUS.FAILED, -1)
    T.assert_eq(Types.AD_STATUS.SHOWN, 0)
    T.assert_eq(Types.AD_STATUS.CLICKED, 3)
    T.assert_truthy(Types.is_known_platform("taptap"))
    T.assert_truthy(Types.is_known_platform("leyuan"))
    T.assert_truthy(Types.is_known_platform("mock"))
    T.assert_truthy(Types.is_known_platform("none"))
    T.assert_truthy(not Types.is_known_platform("bogus"))
end)

-- Platform detection ---------------------------------------------------------
T.run("platform detects browser via HTML5 system_name", function()
    local p = Platform.create({ sys = { get_sys_info = function() return { system_name = "HTML5" } end } })
    T.assert_eq(p:detect().kind, "browser")
    T.assert_truthy(p:is_browser())
end)

T.run("platform detects desktop", function()
    local p = Platform.create({ sys = { get_sys_info = function() return { system_name = "Darwin" } end } })
    T.assert_eq(p:detect().kind, "desktop")
    T.assert_truthy(p:is_desktop())
end)

T.run("platform detects mobile", function()
    local p = Platform.create({ sys = { get_sys_info = function() return { system_name = "Android" } end } })
    T.assert_eq(p:detect().kind, "mobile")
    T.assert_truthy(p:is_mobile())
end)

T.run("platform override wins", function()
    local p = Platform.create({ sys = { get_sys_info = function() return { system_name = "HTML5" } end }, override = { kind = "desktop" } })
    T.assert_eq(p:detect().kind, "desktop")
end)

-- Analytics ------------------------------------------------------------------
T.run("analytics tracks events", function()
    local events = {}
    local a = Analytics.create({ logger = function(event, params, meta) events[#events+1] = { event = event, params = params, meta = meta } end })
    T.assert_truthy(a:track("level_start", { level = 3 }))
    T.assert_eq(#events, 1)
    T.assert_eq(events[1].event, "level_start")
    T.assert_eq(events[1].params.level, 3)
    T.assert_eq(events[1].meta.seq, 1)
    T.assert_eq(a:get_seq(), 1)
end)

T.run("analytics rejects invalid event", function()
    local a = Analytics.create({})
    local ok, err = a:track("", {})
    T.assert_nil(ok)
    T.assert_eq(err.code, "invalid_event")
end)

T.run("analytics respects disabled", function()
    local n = 0
    local a = Analytics.create({ logger = function() n = n + 1 end, enabled = false })
    a:track("x", {})
    T.assert_eq(n, 0)
end)

-- Providers ------------------------------------------------------------------
local function make_ctx(js_impl)
    return {
        js = js_impl or function() return nil end,
        log = function() end,
        sleep = function() end,
        now_ms = function() return os.time() * 1000 end,
        decode_json = function(s)
            local ok, decoded = pcall(function() return require("cjson").decode(s) end)
            if ok then return decoded end
            -- minimal JSON fallback for the shapes we emit in tests
            return nil
        end,
    }
end

T.run("provider registry falls back to none", function()
    local p = Providers.create_provider("bogus", make_ctx())
    T.assert_eq(p.id, "none")
    T.assert_truthy(not p:is_supported())
end)

T.run("none provider unsupported", function()
    local p = Providers.create_provider("none", make_ctx())
    T.assert_truthy(not p:is_supported())
    local r = p:show_rewarded({ timeout_ms = 1000 })
    T.assert_truthy(not r.success)
    T.assert_eq(r.reason, "unsupported")
end)

T.run("mock provider rewards after sleep (sync mode)", function()
    local slept = 0
    local ctx = make_ctx()
    ctx.sleep = function(s) slept = s end
    local p = Providers.create_provider("mock", ctx)
    T.assert_truthy(p:is_supported())
    local r = p:show_rewarded({ timeout_ms = 1000 })
    T.assert_truthy(r.success)
    T.assert_eq(r.status, 4)
    T.assert_eq(r.reason, "rewarded")
    T.assert_truthy(r.mocked)
    T.assert_eq(slept, 1.0)
end)

T.run("mock provider chooser override", function()
    local mock = require "framework.platform.providers.mock"
    mock.set_chooser(function() return { success = false, status = 1, reason = "closed" } end)
    local p = Providers.create_provider("mock", make_ctx())
    local r = p:show_rewarded({ timeout_ms = 1000 })
    T.assert_truthy(not r.success)
    T.assert_eq(r.reason, "closed")
    mock.set_chooser(nil)
end)

T.run("mock provider async mode: pending then poll resolves", function()
    local now = 1000
    local ctx = make_ctx()
    ctx.now_ms = function() return now end
    local p = Providers.create_provider("mock", ctx, { async = true, resolve_delay_ms = 500 })
    local r = p:show_rewarded({ request_id = "req-a", timeout_ms = 1000 })
    T.assert_truthy(r.pending, "pending first")
    T.assert_nil(p:poll("req-a"), "not yet resolved")
    now = now + 600
    local settled = p:poll("req-a")
    T.assert_truthy(settled, "resolved after delay")
    T.assert_truthy(settled.success)
    T.assert_eq(settled.reason, "rewarded")
end)

T.run("mock provider async mode: stale request id ignored", function()
    local now = 1000
    local ctx = make_ctx()
    ctx.now_ms = function() return now end
    local p = Providers.create_provider("mock", ctx, { async = true, resolve_delay_ms = 0 })
    p:show_rewarded({ request_id = "req-1", timeout_ms = 1000 })
    now = now + 10
    T.assert_nil(p:poll("req-other"), "wrong request id yields nil")
end)

T.run("taptap provider requires ad_unit_id", function()
    local p = Providers.create_provider("taptap", make_ctx(), { ad_unit_id = "" })
    local ok, err = p:init()
    T.assert_nil(ok)
    T.assert_eq(err.code, "config")
end)

T.run("taptap provider sdk missing", function()
    local p = Providers.create_provider("taptap", make_ctx(function() return { ok = false, reason = "sdk_missing" } end), { ad_unit_id = "x" })
    local ok, err = p:init()
    T.assert_nil(ok)
    T.assert_eq(err.code, "sdk_missing")
end)

T.run("taptap provider supported when js ok", function()
    local p = Providers.create_provider("taptap", make_ctx(function() return { ok = true } end), { ad_unit_id = "x" })
    T.assert_truthy(p:init())
    T.assert_truthy(p:is_supported())
end)

-- taptap 全链路（假 js 执行器模拟两阶段：show 发起 / poll 消费）。
-- 假执行器按 code 特征区分三类调用：
--   init: 含 "__taptap_ad__" 且含 createRewardedVideoAd
--   show: 含 "ad.show()"
--   poll: 含 "JSON.stringify({ pending:true })"
T.run("taptap async full chain: pending -> stale drop -> settle", function()
    local state = { active = nil, result = nil }
    local ctx = make_ctx(function(code)
        if code:find("createRewardedVideoAd", 1, true) then return { ok = true } end
        if code:find("JSON.stringify", 1, true) then
            local r = state.result
            state.result = nil
            if not r then return { pending = true } end
            if state.active and r.request_id ~= state.active then return { stale = true } end
            return r
        end
        if code:find("ad.show()", 1, true) then
            state.active = code:match('__ad_active__ = "([^"]+)"', 1, true)
            return nil
        end
        return nil
    end)
    local p = Providers.create_provider("taptap", ctx, { ad_unit_id = "unit-1" })

    -- 发起：立即 pending
    local r = p:show_rewarded({ request_id = "tap-1", timeout_ms = 120000 })
    T.assert_truthy(r.pending, "show returns pending")

    -- 广告未结束：poll 为 nil
    T.assert_nil(p:poll("tap-1"), "no result yet")

    -- 晚到的旧请求结果（stale）：被丢弃，poll 仍为 nil
    state.result = { request_id = "tap-old", ok = true, reason = "rewarded", status = 4 }
    T.assert_nil(p:poll("tap-1"), "stale result dropped")

    -- 正确的终态：rewarded
    state.result = { request_id = "tap-1", ok = true, reason = "rewarded", status = 4, raw = { x = 1 } }
    local settled = p:poll("tap-1")
    T.assert_truthy(settled, "settled")
    T.assert_truthy(settled.success)
    T.assert_eq(settled.reason, "rewarded")
    T.assert_eq(settled.status, 4)
end)

T.run("leyuan sdk not ready: init false, then ready via poll_init", function()
    local ready = false
    local ctx = make_ctx(function(code)
        if code:find("MetaH5Ad") and code:find("ready") then
            return { ready = ready }
        end
        if code:find("__ad_sdk_load_state__") then return nil end
        return nil
    end)
    local p = Providers.create_provider("leyuan", ctx)
    T.assert_truthy(not p:init(), "not ready first (script injecting)")
    T.assert_truthy(not p:is_supported(), "unsupported until ready")
    ready = true
    T.assert_truthy(p:poll_init(), "ready after load")
    T.assert_truthy(p:is_supported(), "supported once ready")
end)

T.run("leyuan show before ready refuses, after ready goes pending", function()
    local ready = false
    local settled_result = nil
    local ctx = make_ctx(function(code)
        if code:find("MetaH5Ad", 1, true) and code:find("ready", 1, true) then return { ready = ready } end
        if code:find("JSON.stringify", 1, true) then
            local r = settled_result
            settled_result = nil
            if not r then return { pending = true } end
            return r
        end
        if code:find("showAd", 1, true) then return nil end
        return nil
    end)
    local p = Providers.create_provider("leyuan", ctx)

    local refused = p:show_rewarded({ request_id = "l-0", timeout_ms = 1000 })
    T.assert_truthy(not refused.success, "refuse show before ready")
    T.assert_eq(refused.reason, "sdk_not_ready")

    ready = true
    p:poll_init()
    local r = p:show_rewarded({ request_id = "l-1", timeout_ms = 1000 })
    T.assert_truthy(r.pending, "pending after ready")
    settled_result = { request_id = "l-1", ok = true, reason = "rewarded", status = 4 }
    local settled = p:poll("l-1")
    T.assert_truthy(settled and settled.success, "settled rewarded")
end)

-- RewardAd facade ------------------------------------------------------------
local function make_reward(options)
    options = options or {}
    return RewardAd.create({
        platform = options.platform or "mock",
        config = options.config,
        js = options.js or function() return nil end,
        sleep = options.sleep or function() end,
        now_ms = options.now_ms,
        timeout_ms = options.timeout_ms,
        watchdog_grace_ms = options.watchdog_grace_ms,
        out = options.out or function() end,
    })
end

T.run("reward_ad busy reentry (sync settle releases busy)", function()
    local r = make_reward()
    r.provider = {
        id = "mock",
        init = function() return true end,
        is_supported = function() return true end,
        show_rewarded = function(ctx) return { success = true, status = 4, reason = "rewarded", mocked = true } end,
    }
    local res = r:show_rewarded({ tag = "t1" })
    T.assert_truthy(res.success)
    T.assert_truthy(not r:is_busy())
end)

T.run("reward_ad busy reentry during pending", function()
    local now = 1000
    local r = make_reward({ now_ms = function() return now end, config = { async = true, resolve_delay_ms = 5000 } })
    local res1 = r:show_rewarded({ tag = "first" })
    T.assert_truthy(res1.pending, "first goes pending")
    T.assert_truthy(r:is_busy())
    local res2 = r:show_rewarded({ tag = "second" })
    T.assert_truthy(not res2.pending, "reentry returns sync result")
    T.assert_eq(res2.reason, "busy")
end)

T.run("reward_ad async chain: pending -> update poll -> settled + close event", function()
    local now = 1000
    local closed_result = nil
    local r = make_reward({ now_ms = function() return now end, config = { async = true, resolve_delay_ms = 500 } })
    r:on_ad_close(function(res) closed_result = res end)

    local res = r:show_rewarded({ tag = "revive" })
    T.assert_truthy(res.pending, "pending")
    T.assert_truthy(r:is_busy(), "busy while pending")

    T.assert_nil(r:update(), "no settle before delay")
    T.assert_truthy(r:is_busy(), "still busy")

    now = now + 600
    local settled = r:update()
    T.assert_truthy(settled, "settled via update")
    T.assert_truthy(settled.success)
    T.assert_eq(settled.reason, "rewarded")
    T.assert_eq(settled.request_id, res.request_id, "request id carried through")
    T.assert_truthy(not r:is_busy(), "busy released")
    T.assert_truthy(closed_result ~= nil, "close event fired")
    T.assert_eq(closed_result.reason, "rewarded")
end)

T.run("reward_ad watchdog settles timeout and releases busy", function()
    local now = 1000
    local closed_result = nil
    local r = make_reward({
        now_ms = function() return now end,
        timeout_ms = 1000,
        watchdog_grace_ms = 500,
        config = { async = true, resolve_delay_ms = 100000 }, -- never resolves
    })
    r:on_ad_close(function(res) closed_result = res end)

    local res = r:show_rewarded({ tag = "stuck" })
    T.assert_truthy(res.pending)

    now = now + 1500
    T.assert_nil(r:update(), "within window: still pending")

    now = now + 600 -- beyond timeout_ms + grace
    local settled = r:update()
    T.assert_truthy(settled, "watchdog settles")
    T.assert_truthy(not settled.success)
    T.assert_eq(settled.reason, "timeout")
    T.assert_truthy(not r:is_busy(), "busy released by watchdog")
    T.assert_eq(closed_result.reason, "timeout", "close event carries timeout")
end)

T.run("reward_ad stale result never pollutes next request", function()
    -- async mock: request 1 stuck beyond watchdog; its "late" result arrives
    -- only after request 2 has been issued. The provider poll keying by
    -- request_id must keep request 2 pending.
    local now = 1000
    local resolve_delay = 100000
    local r = make_reward({ now_ms = function() return now end, config = { async = true, resolve_delay_ms = resolve_delay } })

    local res1 = r:show_rewarded({ tag = "one" })
    T.assert_truthy(res1.pending)

    -- Force settle request 1 via watchdog.
    now = now + 200000
    local settled1 = r:update()
    T.assert_eq(settled1.reason, "timeout")

    -- Simulate the late JS result of request 1 arriving: the mock provider
    -- stores it under request 1's id; a new show gets a new id.
    local res2 = r:show_rewarded({ tag = "two" })
    T.assert_truthy(res2.pending)
    T.assert_truthy(res2.request_id ~= res1.request_id, "distinct request ids")

    -- Request 2 must not settle from request 1's stored result before its own
    -- delay elapses; and even then the provider only returns its own result.
    T.assert_nil(r:update(), "request 2 not polluted by request 1's result")
end)

T.run("reward_ad grant_once idempotent", function()
    local r = make_reward()
    local granted = 0
    local rid = "req-1"
    T.assert_truthy(r:grant_once(rid, function() granted = granted + 1 end))
    T.assert_eq(granted, 1)
    T.assert_truthy(not r:grant_once(rid, function() granted = granted + 1 end))
    T.assert_eq(granted, 1)
    T.assert_truthy(r:was_granted(rid))
end)

T.run("reward_ad grant_once rejects empty id", function()
    local r = make_reward()
    T.assert_truthy(not r:grant_once("", function() end))
    T.assert_truthy(not r:grant_once(nil, function() end))
end)

T.run("reward_ad grant rollback on error", function()
    local r = make_reward()
    local ok = pcall(function() r:grant_once("req-2", function() error("boom") end) end)
    T.assert_truthy(not ok)
    T.assert_truthy(not r:was_granted("req-2"))
end)

T.run("reward_ad open/close events", function()
    local r = make_reward()
    local opened, closed = 0, nil
    r:on_ad_open(function() opened = opened + 1 end)
    r:on_ad_close(function(res) closed = res end)
    local res = r:show_rewarded({ tag = "t" })
    T.assert_eq(opened, 1)
    T.assert_truthy(closed ~= nil)
    T.assert_truthy(res.success)
end)

T.run("reward_ad set_platform clears provider", function()
    local r = make_reward()
    r:set_platform("none")
    T.assert_eq(r:get_platform_id(), "none")
    T.assert_truthy(not r:is_supported())
end)

T.run("reward_ad fallback unknown platform to none", function()
    local r = make_reward({ platform = "bogus" })
    T.assert_truthy(not r:is_supported())
end)

-- UI manager transition timeout ----------------------------------------------
local UI = require "framework.ui.ui_manager"
T.run("ui_manager timeout recovers lost transition callback", function()
    local now = 1000
    local adapter = {
        is_busy = function() return false end,
        top = function() return nil end, -- 空栈：open 不会被 already_open 拒绝
        has_history = function() return false end,
        show = function(_, id, data, finish)
            -- 模拟回调丢失：永不调用 finish
        end,
        back = function(_, finish) end,
    }
    -- 注入可控时钟，确定性地驱动超时判定。
    local ui = UI.create({ home = {} }, adapter, { transition_timeout_ms = 5000, now_ms = function() return now end })
    local done_err = nil
    ui:open("home", nil, function(_, err) done_err = err end)
    T.assert_truthy(ui:is_busy(), "busy during pending transition")

    ui:update(now + 1000)
    T.assert_truthy(ui:is_busy(), "within window: still busy")

    ui:update(now + 6000)
    T.assert_truthy(not ui:is_busy(), "timeout releases busy")
    T.assert_truthy(done_err ~= nil, "done called with error")
    T.assert_eq(done_err.code, "transition_timeout")
end)

os.exit(T.summary() == 0 and 0 or 1)
