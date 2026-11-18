-- ItemCard is a tappable card with a title, subtitle and optional price/icon.
-- Display + selection only; it exposes data and an optional on_select callback.
local M = {}

function M.create(druid, nodes, options)
    options = options or {}
    assert(nodes and nodes.title, "item card title node required")
    local self = { druid = druid, data = options.data }
    self.title_node = gui.get_node(nodes.title)
    self.subtitle_node = nodes.subtitle and gui.get_node(nodes.subtitle) or nil
    self.price_node = nodes.price and gui.get_node(nodes.price) or nil
    self.icon_node = nodes.icon and gui.get_node(nodes.icon) or nil
    self.disabled = false

    if nodes.trigger and options.on_select then
        self.button = druid:new_button(nodes.trigger, function()
            if not self.disabled and options.on_select then options.on_select(self, self.data) end
        end, nil, nodes.anim)
    end

    function self:set_data(data) self.data = data end

    function self:set_title(text) gui.set_text(self.title_node, text or "") end

    function self:set_subtitle(text)
        if self.subtitle_node then gui.set_text(self.subtitle_node, text or "") end
    end

    function self:set_price(text)
        if self.price_node then gui.set_text(self.price_node, text or "") end
    end

    function self:set_icon(atlas, image)
        if self.icon_node and atlas then gui.play_flipbook(self.icon_node, atlas, image) end
    end

    function self:set_enabled(enabled)
        self.disabled = not enabled
        if self.button and self.button.set_enabled then self.button:set_enabled(enabled) end
    end

    return self
end

return M
