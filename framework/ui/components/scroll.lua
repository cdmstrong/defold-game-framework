-- Scroll wrapper around a Druid scroll. Delegates to Druid's scroll component
-- and exposes a minimal interface for business callers.
local M = {}

function M.create(druid, nodes, options)
    options = options or {}
    assert(nodes and nodes.view and nodes.content, "scroll view/content nodes required")
    local self = { druid = druid }
    self.scroll = druid:new_scroll(nodes.view, nodes.content)

    function self:scroll_to(pos)
        self.scroll:scroll_to(pos)
    end

    function self:get_percent()
        return self.scroll:get_percent()
    end

    return self
end

return M
