-- Tab bar: a set of selectable tabs with a single active index.
-- Exposes selection state and on_change callback; it does not switch content itself.
local M = {}

function M.create(druid, nodes, options)
    options = options or {}
    assert(nodes and nodes.tabs, "tab nodes required")
    local self = { druid = druid, active = 0 }
    self.tabs = {}
    for i, spec in ipairs(nodes.tabs) do
        local button = druid:new_button(spec.trigger, function()
            self:set_active(i)
            if options.on_change then options.on_change(self, i) end
        end, nil, spec.anim)
        self.tabs[i] = { spec = spec, button = button, active = false }
    end

    function self:set_active(index)
        self.active = index
        for i, tab in ipairs(self.tabs) do
            tab.active = (i == index)
            if tab.spec.active_marker then
                local marker = gui.get_node(tab.spec.active_marker)
                if marker then gui.set_enabled(marker, tab.active) end
            end
        end
    end

    function self:get_active() return self.active end

    return self
end

return M
