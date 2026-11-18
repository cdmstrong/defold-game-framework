-- TapTap 小游戏激励视频 provider。
--
-- TapTap 小游戏宿主会注入全局对象 `tap`，无需额外 SDK。
-- API（官方文档）：
--   tap.createRewardedVideoAd({ adUnitId }) -> 单例 RewardedVideoAd
--   rewardedVideoAd.show()  -> Promise（素材未加载完成会 reject）
--   rewardedVideoAd.onLoad(fn) / onError(err) / onClose(res)
--   onClose 的 res.isEnded === true 才发奖
--
-- 依赖 ctx.js(code) 执行 JavaScript（Defold HTML5 用 html5.run），通过
-- window.__ad_result__ 回传结果；纯 Lua 测试注入假 js 执行器驱动。

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

local function make_show_js()
    return [[
(function() {
  var ad = window.__taptap_ad__;
  if (!ad || typeof ad.show !== 'function') { window.__ad_result__ = { ok:false, reason:'sdk_missing' }; return; }
  var settled = false;
  function settle(r){ if(settled) return; settled = true; window.__ad_result__ = r; }

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

function M.create(ctx, config)
    config = config or {}
    local self = {
        id = "taptap",
        ctx = ctx,
        ad_unit_id = config.ad_unit_id or "",
        require_ad_unit_id = config.require_ad_unit_id ~= false,
        support_cache = nil,
    }

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
        for k, v in pairs(subst) do
            out = out:gsub(k, tostring(v))
        end
        return out
    end

    function self:init()
        if self.ad_unit_id == "" and self.require_ad_unit_id then
            return nil, { code = "config", message = "taptap ad_unit_id is required" }
        end
        local js = make_js(make_init_js(self.ad_unit_id), { "__AD_UNIT_ID__", self.ad_unit_id })
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

    function self:show_rewarded(show_ctx)
        local ok, err = self:init()
        if not ok then
            ctx.log("taptap_init_failed", err and err.message or "init failed")
            return { success = false, status = nil, reason = err and err.code or "sdk_missing", error = err }
        end
        local js = make_js(make_show_js(), { "__TIMEOUT__", show_ctx.timeout_ms })
        local res = run_js(js)
        res = type(res) == "table" and res or {}
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
        ctx.js("(function(){ try { if (window.__taptap_ad__ && window.__taptap_ad__.destroy) window.__taptap_ad__.destroy(); } catch(e){} window.__taptap_ad__ = null; })()")
    end

    return self
end

return M
