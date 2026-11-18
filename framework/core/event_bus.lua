local M = {}
function M.create(options)
    options = options or {}
    local self = { topics = {}, queue = {}, dispatching = false, count = 0 }
    local limit = options.max_dispatches or 256
    assert(limit >= 1, "positive dispatch limit required")
    function self:subscribe(topic, fn)
        assert(type(topic) == "string" and type(fn) == "function", "topic and listener required")
        local item = { fn = fn, active = true }
        local list = self.topics[topic] or {}
        self.topics[topic] = list
        list[#list + 1] = item
        self.count = self.count + 1
        return function()
            if not item.active then return end
            item.active = false
            self.count = self.count - 1
            for i = #list, 1, -1 do if list[i] == item then table.remove(list, i) end end
            if #list == 0 and self.topics[topic] == list then self.topics[topic] = nil end
        end
    end
    function self:emit(topic, payload)
        self.queue[#self.queue + 1] = { topic, payload }
        if self.dispatching then return true end
        self.dispatching = true
        local first_error, index = nil, 1
        while index <= #self.queue do
            if index > limit then
                first_error = { code = "event_loop", message = "Event dispatch limit exceeded" }
                break
            end
            local entry = self.queue[index]
            local snapshot = {}
            for i, item in ipairs(self.topics[entry[1]] or {}) do snapshot[i] = item end
            for _, item in ipairs(snapshot) do
                if item.active then
                    local ok, err = pcall(item.fn, entry[2])
                    if not ok then
                        first_error = first_error or { code = "listener_error", message = tostring(err), topic = entry[1] }
                        if options.logger then pcall(options.logger, entry[1], tostring(err)) end
                    end
                end
            end
            index = index + 1
        end
        self.queue = {}
        self.dispatching = false
        if first_error then return nil, first_error end
        return true
    end
    function self:clear()
        for _, list in pairs(self.topics) do
            for _, item in ipairs(list) do item.active = false end
        end
        self.topics, self.queue, self.count = {}, {}, 0
    end
    function self:listener_count() return self.count end
    return self
end
return M
