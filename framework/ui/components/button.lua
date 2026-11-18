-- Reusable Button component wrapping a Druid button.
-- Exposes data/state/callbacks only; never touches game logic.
local M = {}

-- nodes: { trigger = "node_id", anim = "node_id"|nil, label = "label_node_id"|nil }
-- options: { on_click = function(button), params = any }
function M.create(druid, nodes, options)
    options = options or {}
    assert(nodes and nodes.trigger, "button trigger node required")
    local self = { druid = druid, disabled = false }
    self.button = druid:new_button(nodes.trigger, function(_, params)
        if not self.disabled and options.on_click then options.on_click(self, params) end
    end, options.params, nodes.anim)

    function self:set_enabled(enabled)
        self.disabled = not enabled
        if self.button.set_enabled then self.button:set_enabled(enabled) end
        -- The label is presentation only; keep its text visible regardless of
        -- enabled state so a disabled button is still identifiable.
        if nodes.label then
            local label = gui.get_node(nodes.label)
            if label and options.dim_label then
                local c = gui.get_color(label)
                gui.set_color(label, vmath.vector4(c.x, c.y, c.z, enabled and 1 or 0.45))
            end
        end
    end

    function self:is_enabled() return not self.disabled end

    function self:set_label(text)
        if nodes.label then gui.set_text(gui.get_node(nodes.label), text or "") end
    end

    function self:dispose()
        -- Druid buttons are finalized with the druid instance; nothing to free here.
    end

    return self
end

return M
