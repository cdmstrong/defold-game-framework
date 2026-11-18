-- Tycoon kit stays independent of any particular game state.
package.path = "./?.lua;./?/init.lua;" .. package.path
local T = require "tests.lua.harness"
local Header = require "game_modules.tycoon.ui.currency_header"
local Upgrades = require "game_modules.tycoon.ui.upgrade_list"

T.run("currency formatting and binding", function()
    local nodes = {}
    gui = {
        get_node = function(id) nodes[id] = nodes[id] or { id = id }; return nodes[id] end,
        set_text = function(node, text) node.text = text end,
    }
    T.assert_eq(Header.format_amount(1234567), "1,234,567")
    T.assert_eq(Header.format_amount(-1234), "-1,234")
    local bar = Header.create({}, { value = "economy/value", income = "economy/income" })
    bar:set_value(12500); bar:set_income(42)
    T.assert_eq(nodes["economy/value"].text, "12,500")
    T.assert_eq(nodes["economy/income"].text, "42 /s")
end)

T.run("upgrade rows forward a game callback without mutating data", function()
    local nodes, callbacks = {}, {}
    gui = {
        get_node = function(id) nodes[id] = nodes[id] or { id = id }; return nodes[id] end,
        set_text = function(node, text) node.text = text end,
    }
    local druid = { new_button = function(_, id, callback)
        callbacks[id] = callback
        return { set_enabled = function(self, enabled) self.enabled = enabled end }
    end }
    local selected
    local list = Upgrades.create(druid, { { id = "speed", trigger = "speed_button", label = "speed_label", on_select = function(id) selected = id end } })
    local data = { title = "Speed", level = 2, cost = "1,000", enabled = false }
    list:set_row("speed", data)
    T.assert_eq(nodes.speed_label.text, "Speed Lv.2 → 3 (1,000)")
    T.assert_eq(data.level, 2)
    callbacks.speed_button()
    T.assert_eq(selected, nil)
    list:set_row("speed", { title = "Speed", enabled = true })
    callbacks.speed_button()
    T.assert_eq(selected, "speed")
end)

T.summary()
