-- 广告模块公共类型与常量。
--
-- 刻意不依赖 Defold 引擎、也不依赖具体平台全局对象，这样同一套业务代码
-- 可以在 HTML5 / 小游戏 / 原生壳里复用。纯 Lua，可直接跑单测。
--
-- 对齐 cocos-template 的 AdTypes.ts 语义。

local M = {}

-- 内置平台 id。新增渠道用 register_provider 注册，不需要改这里。
M.KNOWN_PLATFORMS = { "taptap", "leyuan", "mock", "none" }

-- 广告回调状态码（233 乐园 MetaH5Ad 语义，其它平台会在 provider 里映射到
-- 同一套编码）。关键：0 / 3 是过程态，只有 4 才是奖励态。
M.AD_STATUS = {
    FAILED = -1,  -- 播放失败，终态，不发奖
    SHOWN = 0,    -- 展示成功，过程态，继续等待
    CLOSED = 1,   -- 用户关闭，终态，不发奖
    SKIPPED = 2,  -- 用户跳过，终态，不发奖
    CLICKED = 3,  -- 用户点击广告，过程态，继续等待
    REWARDED = 4, -- 发放奖励，终态，发奖
}

-- 结果原因。成功只有 'rewarded'，其余都视为不发奖。
M.REASONS = {
    REWARDED = "rewarded",
    SDK_MISSING = "sdk_missing",
    UNSUPPORTED = "unsupported",
    FAILED = "failed",
    CLOSED = "closed",
    SKIPPED = "skipped",
    TIMEOUT = "timeout",
    EXCEPTION = "exception",
    BUSY = "busy",
    INIT_FAILED = "init_failed",
    UNKNOWN = "unknown",
}

-- 平台展示名，用于日志与调试面板。
M.PLATFORM_LABEL = {
    taptap = "TapTap 小游戏",
    leyuan = "233 乐园",
    mock = "模拟广告",
    none = "无广告",
}

-- 判断一个值是否内置平台 id。
function M.is_known_platform(value)
    for _, id in ipairs(M.KNOWN_PLATFORMS) do
        if value == id then return true end
    end
    return false
end

return M
