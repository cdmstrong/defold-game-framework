-- Miner 各页面视图：渲染 + 按钮绑定。游戏逻辑在 game.lua，这里只读快照。
local Screen = require "framework.ui.screen"
local Button = require "framework.ui.components.button"
local context = require "examples.miner.context"
local Game = require "examples.miner.game"
local CurrencyHeader = require "game_modules.tycoon.ui.currency_header"
local UpgradeList = require "game_modules.tycoon.ui.upgrade_list"
local M = {}

local function send(message, data) msg.post("main:/bootstrap#script", message, data or {}) end

local fmt_coins = CurrencyHeader.format_amount

function M.init(self, id)
    self.id, self.alive = id, true
    self.screen = Screen.create(id, { context = self })
    local druid = self.screen.druid
    local function button(node, fn) return druid:new_button(node, fn) end

    self.buttons = {}
    if id == "mine" then
        self.currency = CurrencyHeader.create(druid, { value = "currency_header/value", income = "currency_header/income" })
    elseif id == "shop" or id == "upgrade" then
        self.currency = CurrencyHeader.create(druid, { value = "coins" })
    end

    if id == "mine" then
        -- 挖矿主区：点击加金币
        self.buttons.mine = button("mine", function() send("click") end)
        button("shop", function() send("navigate", { route = "shop" }) end)
        button("upgrade", function() send("navigate", { route = "upgrade" }) end)
        button("settings", function() send("navigate", { route = "settings" }) end)
    elseif id == "shop" then
        self.buttons.hire = button("hire", function() send("hire") end)
        button("back", function() send("back") end)
    elseif id == "upgrade" then
        self.upgrades = UpgradeList.create(druid, {
            { id = "click", trigger = "up_click", label = "up_click_label", on_select = function() send("up_click") end },
            { id = "miner", trigger = "up_miner", label = "up_miner_label", on_select = function() send("up_miner") end },
            { id = "offline", trigger = "up_offline", label = "up_offline_label", on_select = function() send("up_offline") end },
        })
        button("back", function() send("back") end)
    elseif id == "settings" then
        button("mute", function() send("mute") end)
        button("locale", function() send("locale") end)
        button("ad", function() send("ad") end)
        button("back", function() send("back") end)
    else -- dialog
        button("confirm", function() send("confirm") end)
        button("cancel", function() send("back") end)
    end

    local url = msg.url()
    self.unsubscribe = context.bus:subscribe("changed", function()
        if self.alive then msg.post(url, "refresh") end
    end)
    M.refresh(self)
    print("MINER_VIEW_INIT " .. id)
end

function M.refresh(self)
    local g = context.game
    if not g then return end

    if self.id == "mine" then
        self.currency:set_value(g.coins)
        self.currency:set_income(Game.income_per_second(g))
        local lvl = gui.get_node("miner_count")
        if lvl then gui.set_text(lvl, "矿工 " .. g.miners .. " 名 · 点击 +" .. Game.click_gain(g)) end
    elseif self.id == "shop" then
        self.currency:set_value(g.coins)
        local cost = Game.miner_cost(g)
        local hire_btn = gui.get_node("hire")
        if hire_btn then
            gui.set_text(gui.get_node("hire_label"), "雇佣矿工 " .. fmt_coins(cost))
        end
        gui.set_text(gui.get_node("miner_count"), "矿工 " .. g.miners .. " 名 · 产出 " .. fmt_coins(Game.income_per_second(g)) .. " /s")
    elseif self.id == "upgrade" then
        self.currency:set_value(g.coins)
        self.upgrades:set_row("click", { title = "点击收益", level = g.click_level, cost = fmt_coins(Game.click_upgrade_cost(g)) })
        self.upgrades:set_row("miner", { title = "矿工产量", level = g.miner_level, cost = fmt_coins(Game.miner_upgrade_cost(g)) })
        self.upgrades:set_row("offline", { title = "离线收益", level = g.offline_level, cost = fmt_coins(Game.offline_upgrade_cost(g)) })
    elseif self.id == "settings" then
        local l = context.l10n
        gui.set_text(gui.get_node("locale_label"), "语言: " .. (context.locale == "zh" and "中文" or "English"))
        gui.set_text(gui.get_node("mute_label"), context.settings:get("muted") and "取消静音" or "静音")
    elseif self.id == "dialog" then
        if context.dialog_text then
            gui.set_text(gui.get_node("description"), context.dialog_text)
        end
    end
end

function M.update(self, dt)
    self.screen:update(dt)
end

function M.input(self, action_id, action)
    if context.ui:is_busy() then return true end
    if (action_id == hash("key_esc") or action_id == hash("key_back")) and action.pressed then
        if self.id ~= "mine" then send("back") end
        return true
    end
    return self.screen.druid:on_input(action_id, action) or self.id == "dialog"
end

function M.message(self, message_id, message, sender)
    if message_id == hash("refresh") then M.refresh(self) end
    self.screen:on_message(message_id, message, sender)
end

function M.final(self)
    self.alive = false
    self.unsubscribe()
    self.screen:dispose()
    print("MINER_VIEW_FINAL " .. self.id)
end

return M
