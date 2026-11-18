-- Repeated upgrade rows. Values and callbacks come from the game controller.
local Button = require "framework.ui.components.button"
local M = {}
function M.create(druid, rows)
    local self = { rows = {} }
    for _, spec in ipairs(rows) do
        assert(spec.id and spec.trigger and spec.label, "upgrade row requires id, trigger, label")
        assert(not self.rows[spec.id], "duplicate upgrade row")
        local button = Button.create(druid, { trigger = spec.trigger, label = spec.label }, { on_click = function()
            if spec.on_select then spec.on_select(spec.id) end
        end })
        self.rows[spec.id] = button
    end
    function self:set_row(id, data)
        local button = assert(self.rows[id], "unknown upgrade row")
        local label = data.title or ""
        if data.level then label = label .. " Lv." .. data.level .. " → " .. (data.level + 1) end
        if data.cost then label = label .. " (" .. tostring(data.cost) .. ")" end
        button:set_label(label)
        button:set_enabled(data.enabled ~= false)
    end
    return self
end
return M
