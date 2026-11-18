-- CurrencyBar displays an amount with an icon and optional label.
-- Display-only: it does not hold or mutate economic state.
local M = {}

function M.create(druid, nodes, options)
    options = options or {}
    assert(nodes and nodes.value, "currency value node required")
    local self = { druid = druid }
    self.value_node = gui.get_node(nodes.value)
    self.icon_node = nodes.icon and gui.get_node(nodes.icon) or nil
    self.symbol = options.symbol or ""
    self.format = options.format  -- optional function(amount) -> string

    function self:set_value(amount)
        local text
        if self.format then
            text = self.format(amount)
        else
            text = self.symbol .. tostring(amount)
        end
        gui.set_text(self.value_node, text)
    end

    return self
end

return M
