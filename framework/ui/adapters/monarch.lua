local monarch = require "monarch.monarch"
local M = {}
function M.create(routes)
    local self = { pending = nil, disposed = false }
    local ids = {}
    for id in pairs(routes) do ids[hash(id)] = id end
    function self:top() return ids[monarch.top()] end
    function self:has_history() return monarch.top(-1) ~= nil end
    function self:is_busy() return self.pending ~= nil or monarch.is_busy() end
    local function start(expected, done, invoke)
        local request = { expected = expected, done = done, completed = false }
        self.pending = request
        local ok, detail = pcall(invoke, function() request.completed = true end)
        if not ok then request.error = { code = "transition_failed", message = tostring(detail) }; request.completed = true end
    end
    function self:show(id, data, done)
        start(id, done, function(cb) monarch.show(hash(id), { clear = true }, data, cb) end)
    end
    function self:back(done)
        start(ids[monarch.top(-1)], done, function(cb) monarch.back(nil, nil, cb) end)
    end
    function self:on_message(message_id)
        if message_id == monarch.SCREEN_TRANSITION_FAILED and self.pending then
            self.pending.error = { code = "transition_failed", message = "Monarch could not load the screen" }
        end
    end
    function self:update()
        local request = self.pending
        if not request or not request.completed or monarch.is_busy() then return end
        self.pending = nil
        local err = request.error
        if self:top() ~= request.expected then err = err or { code = "transition_failed", message = "Unexpected visible route" } end
        request.done(err and nil or { route = self:top() }, err)
    end
    function self:dispose() self.disposed = true; self.pending = nil end
    return self
end
return M
