-- ConfirmDialog: a modal confirmation with confirm/cancel actions.
-- It is UI-only; pause blocking is owned by the UI manager, not this component.
local M = {}

function M.create(druid, nodes, options)
    options = options or {}
    assert(nodes and nodes.confirm, "confirm node required")
    local self = { druid = druid }
    self.title_node = nodes.title and gui.get_node(nodes.title) or nil
    self.message_node = nodes.message and gui.get_node(nodes.message) or nil

    self.confirm_button = druid:new_button(nodes.confirm, function()
        if options.on_confirm then options.on_confirm(self) end
    end, nil, nodes.confirm_anim)

    if nodes.cancel then
        self.cancel_button = druid:new_button(nodes.cancel, function()
            if options.on_cancel then options.on_cancel(self) end
        end, nil, nodes.cancel_anim)
    end

    function self:set_title(text)
        if self.title_node then gui.set_text(self.title_node, text or "") end
    end

    function self:set_message(text)
        if self.message_node then gui.set_text(self.message_node, text or "") end
    end

    return self
end

return M
