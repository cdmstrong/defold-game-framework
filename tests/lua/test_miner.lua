-- Miner game logic tests (pure Lua).
package.path = "./?.lua;./?/init.lua;../?.lua;../?/init.lua;" .. package.path

local T = require "tests.lua.harness"
local Game = require "examples.miner.game"

T.run("click adds gain and increments", function()
    local s = Game.create(Game.defaults())
    T.assert_eq(Game.click_gain(s), 1)
    local gain = Game.click(s)
    T.assert_eq(gain, 1)
    T.assert_eq(s.coins, 1)
    T.assert_eq(s.clicks, 1)
end)

T.run("click upgrade increases click gain", function()
    local s = Game.create(Game.defaults())
    s.coins = 1000
    T.assert_eq(Game.click_upgrade_cost(s), 50)
    Game.upgrade_click(s)
    T.assert_eq(s.click_level, 1)
    T.assert_eq(Game.click_gain(s), 2)
    -- next cost grows by 1.6x
    T.assert_eq(Game.click_upgrade_cost(s), 80)
end)

T.run("click upgrade insufficient", function()
    local s = Game.create(Game.defaults())
    local ok, err = Game.upgrade_click(s)
    T.assert_nil(ok)
    T.assert_eq(err.code, "insufficient")
end)

T.run("miner cost grows 1.5x and hire works", function()
    local s = Game.create(Game.defaults())
    T.assert_eq(Game.miner_cost(s), 10)
    s.coins = 100
    Game.hire_miner(s)
    T.assert_eq(s.miners, 1)
    T.assert_eq(s.coins, 90)
    T.assert_eq(Game.miner_cost(s), 15) -- 10 * 1.5
    T.assert_eq(Game.income_per_second(s), 1)
end)

T.run("miner upgrade increases income", function()
    local s = Game.create(Game.defaults())
    s.coins = 1000
    s.miners = 1
    T.assert_eq(Game.income_per_second(s), 1)
    Game.upgrade_miner(s)
    T.assert_eq(s.miner_level, 1)
    -- 1 miner * (1 + 1*0.1) = 1.1 -> income_per_second returns float
    T.assert_eq(Game.income_per_second(s), 1.1)
end)

T.run("offline settle caps at 8h", function()
    local s = Game.create(Game.defaults())
    s.miners = 1
    s.last_seen = 1000
    -- 10 hours elapsed -> capped to 8h, ratio 0.5 -> 1 * 0.5 * 28800 = 14400
    local gain, seconds = Game.settle_offline(s, 1000 + 10 * 3600)
    T.assert_eq(seconds, Game.MAX_OFFLINE_SECONDS)
    T.assert_eq(gain, 14400)
    T.assert_eq(s.coins, 14400)
end)

T.run("offline settle no miners gives zero", function()
    local s = Game.create(Game.defaults())
    s.last_seen = 1000
    local gain, seconds = Game.settle_offline(s, 1000 + 3600)
    T.assert_eq(gain, 0)
    T.assert_eq(seconds, 0)
end)

T.run("offline settle first run zero", function()
    local s = Game.create(Game.defaults())
    local gain, seconds = Game.settle_offline(s, 5000)
    T.assert_eq(gain, 0)
    T.assert_eq(seconds, 0)
end)

T.run("double reward doubles coins", function()
    local s = Game.create(Game.defaults())
    s.coins = 50
    local gain = Game.double_reward(s)
    T.assert_eq(gain, 50)
    T.assert_eq(s.coins, 100)
end)

T.run("validate accepts valid and rejects invalid", function()
    local ok = Game.validate(Game.defaults())
    T.assert_truthy(ok)
    local bad = Game.defaults()
    bad.coins = -1
    local ok2, err = Game.validate(bad)
    T.assert_truthy(not ok2)
    T.assert_truthy(err ~= nil)
end)

T.run("create fills missing fields from defaults", function()
    local s = Game.create({ coins = 100 })
    T.assert_eq(s.coins, 100)
    T.assert_eq(s.miners, 0)
    T.assert_eq(s.click_level, 0)
end)

os.exit(T.summary() == 0 and 0 or 1)
