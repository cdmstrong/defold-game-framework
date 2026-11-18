-- 挖矿大亨：游戏状态机（纯 Lua，可单测）。
--
-- 只负责数值与状态，不碰 UI / 引擎。view.lua 消费这里暴露的只读快照，
-- bootstrap.script 驱动 tick（自动生产）与离线收益结算。
--
-- 状态字段：
--   coins      number  金币余额
--   total      number  累计总产出（统计用）
--   clicks     number  总点击次数（统计用）
--   click_level number 点击收益等级（收益 = 1 + click_level）
--   miners     number  已雇佣矿工数（每名 1 金币/秒）
--   miner_level number 矿工产量等级（产量倍率 = 1 + miner_level * 0.1）
--   offline_level number 离线收益等级（系数 = 0.5 + offline_level * 0.1）
--   last_seen  number  上次结算时间戳（秒）
--
-- 成本成长：
--   点击升级   cost = 50 * 1.6 ^ click_level      （向上取整）
--   雇佣矿工   cost = 10 * 1.5 ^ miners           （向上取整）
--   矿工产量   cost = 100 * 1.8 ^ miner_level
--   离线收益   cost = 200 * 2.0 ^ offline_level

local M = {}

local MAX_OFFLINE_SECONDS = 8 * 3600 -- 离线收益上限 8 小时

local function ceil(x) return math.ceil(x) end

function M.defaults()
    return {
        coins = 0,
        total = 0,
        clicks = 0,
        click_level = 0,
        miners = 0,
        miner_level = 0,
        offline_level = 0,
        last_seen = 0,
    }
end

function M.create(initial)
    local self = initial or M.defaults()
    -- 保证字段齐全（旧档缺失时兜底）
    local d = M.defaults()
    for k, v in pairs(d) do
        if self[k] == nil then self[k] = v end
    end
    return self
end

-- 每秒自动产出（矿工）
function M.income_per_second(state)
    return state.miners * (1 + state.miner_level * 0.1)
end

-- 点击收益
function M.click_gain(state)
    return 1 + state.click_level
end

-- 点击一次
function M.click(state)
    local gain = M.click_gain(state)
    state.coins = state.coins + gain
    state.total = state.total + gain
    state.clicks = state.clicks + 1
    return gain
end

-- 雇佣下一名矿工的成本
function M.miner_cost(state)
    return ceil(10 * 1.5 ^ state.miners)
end

-- 雇佣一名矿工（返回消耗；钱不够返回 nil, error）
function M.hire_miner(state)
    local cost = M.miner_cost(state)
    if state.coins < cost then
        return nil, { code = "insufficient", message = "not enough coins", need = cost, have = state.coins }
    end
    state.coins = state.coins - cost
    state.miners = state.miners + 1
    return cost
end

-- 升级成本
function M.click_upgrade_cost(state)
    return ceil(50 * 1.6 ^ state.click_level)
end

function M.miner_upgrade_cost(state)
    return ceil(100 * 1.8 ^ state.miner_level)
end

function M.offline_upgrade_cost(state)
    return ceil(200 * 2.0 ^ state.offline_level)
end

-- 升级点击收益
function M.upgrade_click(state)
    local cost = M.click_upgrade_cost(state)
    if state.coins < cost then
        return nil, { code = "insufficient", message = "not enough coins", need = cost, have = state.coins }
    end
    state.coins = state.coins - cost
    state.click_level = state.click_level + 1
    return cost
end

-- 升级矿工产量
function M.upgrade_miner(state)
    local cost = M.miner_upgrade_cost(state)
    if state.coins < cost then
        return nil, { code = "insufficient", message = "not enough coins", need = cost, have = state.coins }
    end
    state.coins = state.coins - cost
    state.miner_level = state.miner_level + 1
    return cost
end

-- 升级离线收益
function M.upgrade_offline(state)
    local cost = M.offline_upgrade_cost(state)
    if state.coins < cost then
        return nil, { code = "insufficient", message = "not enough coins", need = cost, have = state.coins }
    end
    state.coins = state.coins - cost
    state.offline_level = state.offline_level + 1
    return cost
end

-- 离线收益系数
function M.offline_ratio(state)
    return 0.5 + state.offline_level * 0.1
end

-- 结算离线收益：返回 (gain, seconds)。
-- now 与 last_seen 均为秒时间戳。离线超过上限按上限计。
function M.settle_offline(state, now)
    now = now or os.time()
    if state.last_seen == nil or state.last_seen <= 0 or state.miners <= 0 then
        state.last_seen = now
        return 0, 0
    end
    local elapsed = math.max(0, now - state.last_seen)
    if elapsed <= 0 then
        state.last_seen = now
        return 0, 0
    end
    local capped = math.min(elapsed, MAX_OFFLINE_SECONDS)
    local gain = math.floor(M.income_per_second(state) * M.offline_ratio(state) * capped)
    state.coins = state.coins + gain
    state.total = state.total + gain
    state.last_seen = now
    return gain, capped
end

-- 广告翻倍奖励：把当前金币翻一倍（用于 mock 广告 rewarded）。
function M.double_reward(state)
    local gain = state.coins
    state.coins = state.coins + gain
    state.total = state.total + gain
    return gain
end

-- 校验一个存档 payload 是否合法（供 save_manager.validate 使用）。
function M.validate(payload)
    if type(payload) ~= "table" then return false, "payload must be table" end
    for _, k in ipairs({ "coins", "total", "clicks", "click_level", "miners", "miner_level", "offline_level" }) do
        local v = payload[k]
        if type(v) ~= "number" or v < 0 then return false, "invalid " .. k end
    end
    return true
end

M.MAX_OFFLINE_SECONDS = MAX_OFFLINE_SECONDS

return M
