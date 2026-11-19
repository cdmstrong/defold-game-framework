-- 233 乐园（Leyuan）激励视频 provider（MetaH5Ad SDK，V2：异步轮询契约）。
--
-- 对齐 cocos-template 的 LeyuanAdProvider.ts，关键坑点：
-- 1. code === 0 只代表 SDK API 调用成功，不代表能发奖。
-- 2. showAd 的 callback 在一次播放中会触发多次（0 -> 3 -> 4）。
-- 3. status = 0（展示成功）、status = 3（点击广告）是过程态，必须继续等。
-- 4. 只有 status = 4 才是奖励态。
-- 5. 长广告（30s）必须给足等待，默认 120s。
--
-- V2 时序要点（真实环境关键修复）：
-- - SDK 加载（script onload）、isAdSupport 回调、showAd 终态回调全是异步的，
--   js 执行器（html5.run）是同步的——任何「发起后立即读 __ad_result__」的
--   阻塞式写法都会提前失败。本 provider 全部改为发起 + 轮询：
--   * init() 只负责「确保 script 标签已注入」；SDK 是否就绪用每帧检查
--     window.MetaH5Ad 的方式（is_ready / poll_init），超时后允许重试。
--   * is_supported = SDK 已就绪（不做 isAdSupport 预检——无填充时 showAd
--     会自然回调失败态，走 failed/timeout 结算）。
--   * show_rewarded 只发起 + 注册回调，返回 { pending = true }；
--     终态由 JS 写入 window.__ad_result__（携带 request_id），
--     门面每帧 poll(request_id) 消费；stale 结果直接丢弃。
--
-- 依赖 ctx.js(code) 执行 JavaScript；纯 Lua 测试注入假 js 执行器驱动。

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

-- 注入 SDK script 标签。onload/onerror/超时都只写 __ad_sdk_load_state__，
-- 不再等待结果——就绪与否由 Lua 侧每帧 poll_init 检查。
local function make_load_sdk_js(sdk_url, load_timeout_ms)
    return [[
(function() {
  if (window.__ad_sdk_load_state__) { return; }
  window.__ad_sdk_load_state__ = 'loading';
  var done = function(){ window.__ad_sdk_load_state__ = 'loaded'; };
  var fail = function(e){ window.__ad_sdk_load_state__ = 'failed'; window.__ad_sdk_load_error__ = String(e); };
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

-- 发起播放：注册 showAd 回调，settle 时把结果带上 request_id 写入
-- window.__ad_result__。发起时先清旧结果并记录 __ad_active__。
-- 同时把每一次回调的归一化结果追加到 __ad_event_log__，便于真机排查
-- 「status=0/3 到了但 4 没到」还是「4 到了但发奖链路断」。
local function make_show_js(ad_type, request_id, timeout_ms, normalize)
    return [[
(function() {
  var sdk = window.MetaH5Ad;
  window.__ad_event_log__ = [];
  if (!sdk || typeof sdk.showAd !== 'function') { window.__ad_result__ = { request_id:"__REQ_ID__", ok:false, reason:'sdk_missing' }; return; }
  window.__ad_result__ = null;
  window.__ad_active__ = "__REQ_ID__";
  var settled = false;
  function settle(r){ if(settled) return; settled = true; r.request_id = "__REQ_ID__"; r.events = window.__ad_event_log__; window.__ad_result__ = r; }
  setTimeout(function(){ settle({ ok:false, reason:'timeout' }); }, __TIMEOUT__);
  try {
    sdk.showAd(__ADTYPE__, function(raw) {
      window.__ad_raw__ = raw;
      var p = __NORMALIZE__(raw);
      window.__ad_event_log__.push({ code:p.code, status:p.status, isRewarded:p.isRewarded, msg:p.message, raw:(typeof raw==='string'? raw : JSON.stringify(raw)).slice(0,160) });
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

-- 每帧轮询：只消费 request_id 匹配的终态结果；stale 直接清空丢弃。
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

local function make_js(code, subst)
    local out = code
    for _, pair in ipairs(subst) do
        out = out:gsub(pair[1], tostring(pair[2]))
    end
    return out
end

function M.create(ctx, config)
    config = config or {}
    local self = {
        id = "leyuan",
        ctx = ctx,
        ad_type = config.ad_type or 1,
        sdk_url = config.sdk_url or "https://cdn.233xyx.com/h5ad/metah5ad_v1.min.js",
        sdk_load_timeout_ms = config.sdk_load_timeout_ms or 15000,
        init_done = false, -- MetaH5Ad 已确认就绪
        loading_started = false, -- script 标签已注入（结果未确认）
        loading_started_at = 0,
        active_request = nil,
        pending_show = nil, -- 待播请求 { request_id, ad_type, timeout_ms, deadline }：SDK 未就绪时先登记，就绪后真正发起
    }

    local NORMALIZE_INJECTED = NORMALIZE_JS:gsub("__RAW__", "raw")

    -- 执行 JS，返回 table（假执行器直接给表）或解析 JSON 字符串（html5.run）。
    local function run_js(code)
        local res = ctx.js(code)
        if type(res) == "table" then return res end
        if type(res) == "string" and res ~= "" and ctx.decode_json then
            local ok, decoded = pcall(ctx.decode_json, res)
            if ok and decoded then return decoded end
        end
        return res
    end

    -- init：确保 SDK 加载已发起。返回 true（就绪）/ false（未就绪），
    -- 只有配置级错误返回 nil, err。加载超时后允许重新发起。
    function self:init()
        if self.init_done then return true end
        if not self.loading_started then
            ctx.log("leyuan_init", "injecting sdk script")
            run_js(make_js(make_load_sdk_js(self.sdk_url, self.sdk_load_timeout_ms), {
                { "__SDK_URL__", self.sdk_url },
                { "__LOAD_TIMEOUT__", self.sdk_load_timeout_ms },
            }))
            self.loading_started = true
            self.loading_started_at = ctx.now_ms()
            return false
        end
        -- 加载中：超时则允许重试
        if (ctx.now_ms() - self.loading_started_at) > self.sdk_load_timeout_ms then
            ctx.log("leyuan_init_timeout", "sdk load exceeded " .. tostring(self.sdk_load_timeout_ms) .. "ms, will retry")
            self.loading_started = false
        end
        return false
    end

    -- 每帧检查 SDK 是否就绪（真实环境：MetaH5Ad 已注入且关键方法可用；纯 Lua：假执行器模拟）。
    -- 关键：只查对象存在不够——async 注入的 script 可能对象已挂但方法尚未初始化，
    -- 或 showAd 半就绪导致回调被吞（表现为「看完没奖励」）。这里要求
    -- showAd / isAdSupport 均为 function 才算真正就绪。
    function self:poll_init()
        if self.init_done then return true end
        local check = run_js("(function(){var s=window.MetaH5Ad;var ready=!!s && typeof s==='object' && typeof s.showAd==='function' && typeof s.isAdSupport==='function';return JSON.stringify({ready:ready});})()")
        if type(check) == "table" and check.ready then
            self.init_done = true
            ctx.log("leyuan_ready", "sdk loaded")
            return true
        end
        return false
    end

    function self:is_supported()
        -- 未就绪时返回 false 且不缓存（可能是暂时加载中）。
        return self.init_done
    end

    -- 发起播放。SDK 就绪 → 立即发起；未就绪 → 登记 pending_show，等就绪后再真正发起。
    -- 一律立即返回 { pending = true }；结果经 poll(request_id) 获取。
    -- 不再当场拒绝（旧逻辑 sdk_not_ready 会导致「第一次点不动 / 秒失败」，只有重启后
    -- SDK 已缓存预热才走得通）；改为「等待就绪」兜底，弱网冷启动也能拉到广告。
    function self:show_rewarded(show_ctx)
        local request_id = show_ctx.request_id
        local ad_type = self.ad_type
        local timeout_ms = show_ctx.timeout_ms

        -- 就绪超时：SDK 始终没就绪则本次按 timeout 结算（由 poll 判定），
        -- 而不是立刻失败，给 async script 加载留足时间。
        local deadline = ctx.now_ms() + (self.sdk_load_timeout_ms or 15000)

        if self:poll_init() then
            self:_launch_show(request_id, ad_type, timeout_ms)
        else
            ctx.log("leyuan_show_queued", "sdk not ready yet, queueing request_id=" .. tostring(request_id))
            self.pending_show = { request_id = request_id, ad_type = ad_type, timeout_ms = timeout_ms, deadline = deadline }
        end
        self.active_request = request_id
        return { pending = true }
    end

    -- 真正发起 showAd：注入 JS 注册回调，结果带 request_id 写入 __ad_result__。
    function self:_launch_show(request_id, ad_type, timeout_ms)
        local js = make_js(make_show_js(ad_type, request_id, timeout_ms, NORMALIZE_INJECTED), {
            { "__REQ_ID__", request_id },
            { "__ADTYPE__", tostring(ad_type) },
            { "__TIMEOUT__", timeout_ms },
            { "__NORMALIZE__", NORMALIZE_INJECTED },
        })
        run_js(js)
        ctx.log("leyuan_show_started", "request_id=" .. tostring(request_id))
    end

    -- 轮询终态。nil = 未结束；result = 终态（含 stale 丢弃）。
    function self:poll(request_id)
        if self.active_request ~= request_id then return nil end

        -- 待播队列：SDK 还没就绪。就绪后真正发起 showAd，并清掉待播登记。
        if self.pending_show and self.pending_show.request_id == request_id then
            if self:poll_init() then
                local ps = self.pending_show
                self.pending_show = nil
                self:_launch_show(ps.request_id, ps.ad_type, ps.timeout_ms)
                ctx.log("leyuan_show_deferred", "sdk ready, launched request_id=" .. tostring(request_id))
                return nil -- 已发起，继续等终态
            end
            if ctx.now_ms() > self.pending_show.deadline then
                -- SDK 一直没就绪：兜底结算为 sdk_not_ready，交给业务层决定回退。
                self.pending_show = nil
                self.active_request = nil
                ctx.log("leyuan_settled", "sdk_not_ready")
                return { success = false, status = nil, reason = "sdk_not_ready" }
            end
            return nil
        end

        local res = run_js(make_js(make_poll_js(request_id), { { "__REQ_ID__", request_id } }))
        if type(res) ~= "table" then return nil end
        if res.pending then return nil end
        if res.stale then
            -- 晚到的旧请求结果：丢弃，但当前请求仍在进行中，保留 active_request。
            ctx.log("leyuan_stale_dropped", "request_id=" .. tostring(request_id))
            return nil
        end
        self.active_request = nil
        ctx.log("leyuan_settled", tostring(res.reason) .. " status=" .. tostring(res.status))
        return {
            success = res.ok == true,
            status = res.status,
            reason = res.reason or "unknown",
            raw = res.raw,
            error = res.error,
            events = res.events, -- 完整回调序列（诊断用）
        }
    end

    function self:dispose()
        self.init_done = false
        self.loading_started = false
        self.active_request = nil
        self.pending_show = nil
        ctx.js("(function(){ window.__ad_sdk_load_state__ = null; window.MetaH5Ad = undefined; })()")
    end

    return self
end

return M
