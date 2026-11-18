-- TapTap 小游戏激励视频 provider（V2：异步轮询契约）。
--
-- TapTap 小游戏宿主会注入全局对象 `tap`，无需额外 SDK。
-- API（官方文档）：
--   tap.createRewardedVideoAd({ adUnitId }) -> 单例 RewardedVideoAd
--   rewardedVideoAd.show()  -> Promise（素材未加载完成会 reject）
--   rewardedVideoAd.onLoad(fn) / onError(err) / onClose(res)
--   onClose 的 res.isEnded === true 才发奖
--
-- 关键时序：show() 到 onClose 间隔数秒到数十秒，而 js 执行器（html5.run）
-- 是同步的。所以 show_rewarded 只「发起播放 + 注册回调」，立即返回
-- { pending = true }；结果由 JS 回调写入 window.__ad_result__（携带
-- request_id），门面每帧 poll(request_id) 消费。request_id 不匹配的
-- 晚到结果（stale）直接丢弃，绝不污染下一次请求。
--
-- 依赖 ctx.js(code) 执行 JavaScript；纯 Lua 测试注入假 js 执行器驱动。

local M = {}

local function make_init_js(ad_unit_id)
    return [[
(function() {
  if (window.__taptap_ad__) { window.__ad_result__ = { ok:true }; return; }
  var tap = window.tap || (typeof globalThis !== 'undefined' ? globalThis.tap : null);
  if (!tap || typeof tap.createRewardedVideoAd !== 'function') { window.__ad_result__ = { ok:false, reason:'sdk_missing' }; return; }
  try {
    var ad = tap.createRewardedVideoAd({ adUnitId: "__AD_UNIT_ID__" });
    window.__taptap_ad__ = ad;
    window.__ad_result__ = { ok:true };
  } catch(e) { window.__ad_result__ = { ok:false, reason:'init_failed', error:String(e) }; }
})()
]]
end

-- 发起播放：注册 onClose/onError，settle 时把结果带上 request_id 写入
-- window.__ad_result__。发起时先清旧结果并记录 __ad_active__。
local function make_show_js(request_id, timeout_ms)
    return [[
(function() {
  var ad = window.__taptap_ad__;
  if (!ad || typeof ad.show !== 'function') { window.__ad_result__ = { request_id:"__REQ_ID__", ok:false, reason:'sdk_missing' }; return; }
  window.__ad_result__ = null;
  window.__ad_active__ = "__REQ_ID__";
  var settled = false;
  function settle(r){ if(settled) return; settled = true; r.request_id = "__REQ_ID__"; window.__ad_result__ = r; }

  function off(){ if(ad.offClose) ad.offClose(onClose); if(ad.offError) ad.offError(onError); }
  function onClose(res) {
    off();
    var ended = !!(res && res.isEnded === true);
    settle(ended ? { ok:true, reason:'rewarded', status:4, raw:res }
                 : { ok:false, reason:'closed', status:1, raw:res });
  }
  function onError(err) {
    off();
    settle({ ok:false, reason:'failed', status:-1, error:(err && err.errMsg) || String(err) });
  }

  var t = setTimeout(function(){ off(); settle({ ok:false, reason:'timeout' }); }, __TIMEOUT__);

  if (ad.onClose) ad.onClose(onClose);
  if (ad.onError) ad.onError(onError);

  var p = ad.show();
  if (p && typeof p.catch === 'function') {
    p.catch(function(err) {
      /* 素材未加载完成：尝试 load 后重播一次 */
      if (ad.load) {
        ad.load().then(function(){ return ad.show(); }).catch(function(e2){
          off(); clearTimeout(t); settle({ ok:false, reason:'failed', status:-1, error:String(e2 && e2.errMsg || e2) });
        });
      } else {
        off(); clearTimeout(t); settle({ ok:false, reason:'failed', status:-1, error:String(err && err.errMsg || err) });
      }
    });
  }
})()
]]
end

-- 每帧轮询：只消费 request_id 匹配的终态结果；stale（晚到的旧请求结果）
-- 直接清空丢弃。返回 JSON 字符串供 html5.run 同步带回。
local function make_poll_js(request_id)
    return [[
(function() {
  var r = window.__ad_result__;
  if (!r) { return JSON.stringify({ pending:true }); }
  if (r.request_id !== "__REQ_ID__") { window.__ad_result__ = null; return JSON.stringify({ stale:true }); }
  window.__ad_result__ = null;
  return JSON.stringify(r);
})()
]]
end

function M.create(ctx, config)
    config = config or {}
    local self = {
        id = "taptap",
        ctx = ctx,
        ad_unit_id = config.ad_unit_id or "",
        require_ad_unit_id = config.require_ad_unit_id ~= false,
        support_cache = nil,
        active_request = nil, -- 发起中的 request_id（poll 校验用）
    }

    -- 执行一段 JS，返回 table（假执行器直接给表）或解析 JSON 字符串（html5.run）。
    local function run_js(code)
        local res = ctx.js(code)
        if type(res) == "table" then return res end
        if type(res) == "string" and res ~= "" and ctx.decode_json then
            local ok, decoded = pcall(ctx.decode_json, res)
            if ok and decoded then return decoded end
        end
        return res
    end

    local function make_js(code, subst)
        local out = code
        for _, pair in ipairs(subst) do
            out = out:gsub(pair[1], tostring(pair[2]))
        end
        return out
    end

    function self:init()
        if self.ad_unit_id == "" and self.require_ad_unit_id then
            return nil, { code = "config", message = "taptap ad_unit_id is required" }
        end
        local js = make_js(make_init_js(self.ad_unit_id), { { "__AD_UNIT_ID__", self.ad_unit_id } })
        local res = run_js(js)
        if type(res) == "table" and res.ok == false then
            return nil, { code = res.reason or "init_failed", message = res.error or "tap sdk missing" }
        end
        return true
    end

    function self:is_supported()
        if self.support_cache ~= nil then return self.support_cache end
        local ok = self:init()
        self.support_cache = ok and true or false
        return self.support_cache
    end

    -- 发起播放。立即返回 { pending = true }；结果经 poll(request_id) 获取。
    function self:show_rewarded(show_ctx)
        local ok, err = self:init()
        if not ok then
            ctx.log("taptap_init_failed", err and err.message or "init failed")
            return { success = false, status = nil, reason = err and err.code or "sdk_missing", error = err }
        end
        local request_id = show_ctx.request_id
        local js = make_js(make_show_js(request_id, show_ctx.timeout_ms), {
            { "__REQ_ID__", request_id },
            { "__TIMEOUT__", show_ctx.timeout_ms },
        })
        run_js(js)
        self.active_request = request_id
        ctx.log("taptap_show_started", "request_id=" .. tostring(request_id))
        return { pending = true }
    end

    -- 轮询终态。nil = 未结束；result = 终态（含 stale 丢弃）。
    function self:poll(request_id)
        if self.active_request ~= request_id then return nil end
        local res = run_js(make_js(make_poll_js(request_id), { { "__REQ_ID__", request_id } }))
        if type(res) ~= "table" then return nil end
        if res.pending then return nil end
        if res.stale then
            -- 晚到的旧请求结果：丢弃，但当前请求仍在进行中，保留 active_request。
            ctx.log("taptap_stale_dropped", "request_id=" .. tostring(request_id))
            return nil
        end
        self.active_request = nil
        ctx.log("taptap_settled", tostring(res.reason) .. " status=" .. tostring(res.status))
        return {
            success = res.ok == true,
            status = res.status,
            reason = res.reason or "unknown",
            raw = res.raw,
            error = res.error,
        }
    end

    function self:dispose()
        self.support_cache = nil
        self.active_request = nil
        ctx.js("(function(){ try { if (window.__taptap_ad__ && window.__taptap_ad__.destroy) window.__taptap_ad__.destroy(); } catch(e){} window.__taptap_ad__ = null; })()")
    end

    return self
end

return M
