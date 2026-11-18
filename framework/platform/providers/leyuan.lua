-- 233 乐园（Leyuan）激励视频 provider（MetaH5Ad SDK）。
--
-- 对齐 cocos-template 的 LeyuanAdProvider.ts，关键坑点：
-- 1. code === 0 只代表 SDK API 调用成功，不代表能发奖。
-- 2. showAd 的 callback 在一次播放中会触发多次（0 -> 3 -> 4）。
-- 3. status = 0（展示成功）、status = 3（点击广告）是过程态，必须继续等。
-- 4. 只有 status = 4 才是奖励态。
-- 5. 长广告（30s）必须给足等待，默认 120s。
--
-- 依赖 ctx.js(code) 执行 JavaScript（Defold HTML5 用 html5.run），通过
-- window.__ad_result__ 回传结果；纯 Lua 测试注入假 js 执行器驱动。

local M = {}

-- SDK 回调结果归一化：SDK 回调常是「JSON 字符串套一层 response」的形状，
-- 字段名也不统一，这里抹平成 { code, status, message, is_rewarded }。
-- 在 JS 侧做归一化，Lua 侧只消费这一套判断。
local NORMALIZE_JS = [[
(function(raw) {
  var r = raw, d = raw;
  try { if (typeof raw === 'string') { r = JSON.parse(raw); } } catch(e) {}
  for (var i=0;i<5 && r && typeof r === 'object' && r.response !== undefined;i++) { r = r.response; }
  d = r && r.data !== undefined ? r.data : r;
  for (var j=0;j<5 && d && typeof d === 'object' && d.response !== undefined;j++) { d = d.response; }
  function toNum(v){ var n = Number(v); return (v===null||v===undefined||v===''||isNaN(n)) ? null : n; }
  var code = toNum(r && (r.code !== undefined ? r.code : r.errCode));
  var st = null;
  if (d && typeof d === 'object') { st = toNum(d.status !== undefined ? d.status : (d.rewardStatus !== undefined ? d.rewardStatus : d.state)); }
  else { st = toNum(d !== undefined ? d : (r && r.status !== undefined ? r.status : (r && r.rewardStatus !== undefined ? r.rewardStatus : r.state))); }
  var msg = String((r && (r.message !== undefined ? r.message : r.msg)) || (d && typeof d === 'object' && d.message !== undefined ? d.message : '') || '');
  var explicit = !!(r && (r.rewarded === true || r.reward === true || r.completed === true));
  if (!explicit && d && typeof d === 'object') { explicit = !!(d.rewarded === true || d.reward === true || d.completed === true); }
  return { code: code, status: st, message: msg, isRewarded: (st === 4 || explicit) };
})(__RAW__)
]]

local function make_show_js(ad_type)
    return [[
(function() {
  var sdk = window.MetaH5Ad;
  if (!sdk || typeof sdk.showAd !== 'function') { window.__ad_result__ = { ok:false, reason:'sdk_missing' }; return; }
  var settled = false;
  function settle(r){ if(settled) return; settled = true; window.__ad_result__ = r; }
  setTimeout(function(){ settle({ ok:false, reason:'timeout' }); }, __TIMEOUT__);
  try {
    sdk.showAd(__ADTYPE__, function(raw) {
      window.__ad_raw__ = raw;
      var p = __NORMALIZE__(raw);
      if (p.code !== null && p.code !== 0) { settle({ ok:false, reason:'failed', status:p.status, raw:raw }); return; }
      if (p.isRewarded) { settle({ ok:true, reason:'rewarded', status:4, raw:raw }); return; }
      if (p.status === 0 || p.status === 3) { return; } /* 过程态继续等 */
      if (p.status === 1) { settle({ ok:false, reason:'closed', status:1, raw:raw }); return; }
      if (p.status === 2) { settle({ ok:false, reason:'skipped', status:2, raw:raw }); return; }
      if (p.status === -1) { settle({ ok:false, reason:'failed', status:-1, raw:raw }); return; }
      /* 未知状态交给超时兜底 */
    });
  } catch(e) { settle({ ok:false, reason:'exception', error:String(e) }); }
})()
]]
end

local function make_support_js(ad_type)
    return [[
(function() {
  var sdk = window.MetaH5Ad;
  if (!sdk || typeof sdk.isAdSupport !== 'function') { window.__ad_result__ = { ok:false, reason:'sdk_missing' }; return; }
  var settled = false;
  function finish(v){ if(settled) return; settled = true; window.__ad_result__ = { ok:true, supported: v }; }
  setTimeout(function(){ finish(false); }, __SUPPORT_TIMEOUT__);
  try {
    sdk.isAdSupport(__ADTYPE__, function(raw) {
      var p = __NORMALIZE__(raw);
      finish(p.code === 0 && Number(p.status) === 1);
    });
  } catch(e) { finish(false); }
})()
]]
end

local function load_sdk_js(sdk_url)
    return [[
(function() {
  if (window.MetaH5Ad && typeof window.MetaH5Ad === 'object') { window.__ad_result__ = { ok:true }; return; }
  function done(){ window.__ad_result__ = { ok:true }; }
  function fail(e){ window.__ad_result__ = { ok:false, error:String(e) }; }
  var s = document.createElement('script');
  s.src = "__SDK_URL__";
  s.async = true;
  var t = setTimeout(function(){ s.onload=s.onerror=null; fail(new Error('script timeout')); }, __LOAD_TIMEOUT__);
  s.onload = function(){ clearTimeout(t); done(); };
  s.onerror = function(){ clearTimeout(t); fail(new Error('script load failed')); };
  document.head.appendChild(s);
})()
]]
end

function M.create(ctx, config)
    config = config or {}
    local self = {
        id = "leyuan",
        ctx = ctx,
        ad_type = config.ad_type or 1,
        sdk_url = config.sdk_url or "https://cdn.233xyx.com/h5ad/metah5ad_v1.min.js",
        sdk_load_timeout_ms = config.sdk_load_timeout_ms or 15000,
        support_timeout_ms = config.support_timeout_ms or 8000,
        init_done = false,
        support_cache = nil,
    }

    -- 执行 JS 并读取 window.__ad_result__（同步返回值是 ctx.js 的约定）。
    -- 纯 Lua 测试用假 js 执行器直接返回结果表。
    local function run_js(code, result_key)
        local res = ctx.js(code)
        if type(res) == "table" then
            return res
        end
        -- 兼容返回字符串 JSON
        if type(res) == "string" and res ~= "" then
            local ok, decoded = pcall(function() return ctx.decode_json and ctx.decode_json(res) or nil end)
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
        if self.init_done then return true end
        ctx.log("leyuan_init", "loading sdk")
        local js = make_js(load_sdk_js(self.sdk_url), {
            "__SDK_URL__", self.sdk_url,
            "__LOAD_TIMEOUT__", self.sdk_load_timeout_ms,
        })
        local res = run_js(js)
        if type(res) == "table" and res.ok == false then
            return nil, { code = "init_failed", message = res.error or "sdk load failed" }
        end
        -- 校验 SDK 真的存在
        local check = ctx.js("window.MetaH5Ad && typeof window.MetaH5Ad === 'object' ? { ok:true } : { ok:false }")
        if type(check) == "table" and check.ok == false then
            return nil, { code = "init_failed", message = "MetaH5Ad missing after load" }
        end
        self.init_done = true
        return true
    end

    function self:is_supported()
        if self.support_cache ~= nil then return self.support_cache end
        local ok, err = self:init()
        if not ok then
            self.support_cache = false
            return false
        end
        local js = make_js(make_support_js(self.ad_type), {
            "__ADTYPE__", self.ad_type,
            "__SUPPORT_TIMEOUT__", self.support_timeout_ms,
            "__NORMALIZE__", NORMALIZE_JS:gsub("__RAW__", "raw"),
        })
        local res = run_js(js)
        local supported = type(res) == "table" and res.supported == true
        -- 只缓存「支持」；不支持可能是临时的（无填充/网络抖动）
        if supported then self.support_cache = true end
        return supported
    end

    function self:show_rewarded(show_ctx)
        local ok, err = self:init()
        if not ok then
            ctx.log("leyuan_init_failed", err and err.message or "init failed")
            return { success = false, status = nil, reason = "sdk_missing", error = err }
        end
        local js = make_js(make_show_js(self.ad_type), {
            "__ADTYPE__", self.ad_type,
            "__TIMEOUT__", show_ctx.timeout_ms,
            "__NORMALIZE__", NORMALIZE_JS:gsub("__RAW__", "raw"),
        })
        local res = run_js(js)
        res = type(res) == "table" and res or {}
        ctx.log("leyuan_settled", tostring(res.reason) .. " status=" .. tostring(res.status))
        return {
            success = res.ok == true,
            status = res.status,
            reason = res.reason or "unknown",
            raw = res.raw,
            error = res.error,
        }
    end

    function self:dispose()
        self.init_done = false
        self.support_cache = nil
    end

    return self
end

return M
