-- Toast: transient non-blocking message shown in a fixed overlay.
-- Default it does not intercept input. Caller drives show/hide via update.
local M = {}

function M.create(druid, nodes, options)
    options = options or {}
    assert(nodes and nodes.text, "toast text node required")
    local self = { druid = druid, duration = options.duration or 2.0, remaining = 0 }
    self.root = nodes.root and gui.get_node(nodes.root) or nil
    self.text_node = gui.get_node(nodes.text)

    function self:show(message)
        gui.set_text(self.text_node, message or "")
        self.remaining = self.duration
        if self.root then gui.set_enabled(self.root, true) end
    end

    function self:hide()
        self.remaining = 0
        if self.root then gui.set_enabled(self.root, false) end
    end

    function self:update(dt)
        if self.remaining > 0 then
            self.remaining = self.remaining - dt
            if self.remaining <= 0 then self:hide() end
        end
    end

    return self
end

return M
