local druid = require "druid.druid"
local monarch = require "monarch.monarch"
local M = {}
function M.create(id, options)
    options = options or {}
    local self = { id = id, druid = druid.new(options.context), timer = nil, alive = true }
    local root = gui.get_node("root")
    monarch.on_transition(hash(id), function(message_id, _, sender)
        if message_id == monarch.TRANSITION_SHOW_IN or message_id == monarch.TRANSITION_BACK_IN then
            gui.set_color(root, vmath.vector4(1, 1, 1, 0.4))
            gui.animate(root, "color.w", 1, gui.EASING_OUTQUAD, 0.12)
        end
        self.timer = timer.delay(0.12, false, function()
            self.timer = nil
            if self.alive then msg.post(sender, monarch.TRANSITION_DONE) end
        end)
    end)
    function self:update(dt) self.druid:update(dt) end
    function self:on_message(message_id, message, sender)
        monarch.on_message(message_id, message, sender)
        self.druid:on_message(message_id, message, sender)
    end
    function self:dispose()
        if not self.alive then return end
        self.alive = false
        if self.timer then timer.cancel(self.timer); self.timer = nil end
        -- The screen is unregistered by Monarch during the exit transition, so the
        -- transition callback may already be gone. Clearing it is defensive only.
        pcall(monarch.on_transition, hash(self.id), nil)
        self.druid:final()
    end
    return self
end
return M
