local M = {}
function M.create()
    local self = { count = 0, reasons = {} }
    function self:acquire(reason)
        assert(type(reason) == "string" and reason ~= "", "pause reason required")
        self.count = self.count + 1
        self.reasons[reason] = (self.reasons[reason] or 0) + 1
        local released = false
        return function()
            if released then return end
            released = true
            self.count = self.count - 1
            self.reasons[reason] = self.reasons[reason] - 1
            if self.reasons[reason] == 0 then self.reasons[reason] = nil end
        end
    end
    function self:is_paused() return self.count > 0 end
    return self
end
return M
