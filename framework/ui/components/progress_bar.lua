-- Progress bar component wrapping a Druid progress fill.
-- key is "x" (horizontal) or "y" (vertical); value in [0, 1].
local M = {}

function M.create(druid, nodes, options)
    options = options or {}
    assert(nodes and nodes.fill, "progress fill node required")
    local self = { druid = druid, min = options.min or 0, max = options.max or 1 }
    local key = options.key or "x"
    assert(key == "x" or key == "y", "progress key must be 'x' or 'y'")
    self.progress = druid:new_progress(nodes.fill, key, options.initial or 1)

    function self:set_value(value)
        value = math.max(self.min, math.min(self.max, value))
        local ratio = (self.max == self.min) and 0 or ((value - self.min) / (self.max - self.min))
        self.progress:set_value(ratio)
    end

    function self:set_range(min, max)
        assert(max > min, "progress max must exceed min")
        self.min, self.max = min, max
    end

    return self
end

return M
