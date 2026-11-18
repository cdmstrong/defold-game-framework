local M = {}
local function error_value(code, message) return { code = code, message = message or code } end
local function clone(value, seen)
    local t = type(value)
    if t == "nil" or t == "string" or t == "boolean" then return value end
    if t == "number" then assert(value == value and math.abs(value) < math.huge, "nonfinite data"); return value end
    assert(t == "table" and not getmetatable(value), "route data must be plain data")
    seen = seen or {}
    assert(not seen[value], "cyclic route data")
    seen[value] = true
    local copy = {}
    for k, v in pairs(value) do
        assert(type(k) == "string" or type(k) == "number", "invalid data key")
        copy[k] = clone(v, seen)
    end
    seen[value] = nil
    return copy
end
function M.create(routes, adapter, options)
    options = options or {}
    local self = { disposed = false, pending = nil, modal = nil, sequence = 0 }
    local function notify(callback, result, err)
        if not callback then return end
        local ok, detail = pcall(callback, result, err)
        if not ok and options.logger then pcall(options.logger, "callback_error", tostring(detail)) end
    end
    local function available()
        if self.disposed then return nil, error_value("disposed") end
        if self.pending or adapter:is_busy() then return nil, error_value("busy") end
        return true
    end
    local function end_modal(result, err)
        local modal = self.modal
        if not modal then return end
        self.modal = nil
        if modal.release then modal.release() end
        notify(modal.done, result, err)
    end
    local function begin(operation, done, invoke)
        self.sequence = self.sequence + 1
        local request = { id = self.sequence, done = done, operation = operation }
        self.pending = request
        local function finish(result, err)
            if self.pending ~= request then return end
            self.pending = nil
            notify(done, result, err)
        end
        local ok, detail = pcall(invoke, finish)
        if not ok then finish(nil, error_value("transition_failed", tostring(detail))) end
        return request.id
    end
    function self:is_busy() return self.pending ~= nil or adapter:is_busy() end
    function self:open(id, data, done)
        local ok, err = available(); if not ok then return nil, err end
        if not routes[id] then return nil, error_value("unknown_route", tostring(id)) end
        if routes[id].popup then return nil, error_value("use_dialog") end
        if self.modal then return nil, error_value("modal_active") end
        if adapter:top() == id then return nil, error_value("already_open") end
        local copied, value = pcall(clone, data)
        if not copied then return nil, error_value("invalid_data", tostring(value)) end
        return begin("open", done, function(finish) adapter:show(id, value, finish) end)
    end
    function self:dialog(id, data, done)
        local ok, err = available(); if not ok then return nil, err end
        if not routes[id] then return nil, error_value("unknown_route", tostring(id)) end
        if not routes[id].popup then return nil, error_value("not_popup") end
        if self.modal then return nil, error_value("modal_active") end
        if not adapter:top() then return nil, error_value("no_history") end
        local copied, value = pcall(clone, data)
        if not copied then return nil, error_value("invalid_data", tostring(value)) end
        self.modal = { route = id, done = done, release = options.pause and options.pause:acquire("dialog:" .. id) }
        return begin("dialog", function(_, failure)
            if failure then end_modal(nil, failure) end
        end, function(finish) adapter:show(id, value, finish) end)
    end
    function self:back(done)
        local ok, err = available(); if not ok then return nil, err end
        if not adapter:has_history() then return nil, error_value("no_history") end
        return begin("back", function(result, failure)
            if not failure and self.modal then end_modal({ status = "cancelled" }) end
            notify(done, result, failure)
        end, function(finish) adapter:back(finish) end)
    end
    function self:resolve_dialog(value)
        local ok, err = available(); if not ok then return nil, err end
        if not self.modal or adapter:top() ~= self.modal.route then return nil, error_value("no_dialog") end
        local copied, result = pcall(clone, value)
        if not copied then return nil, error_value("invalid_data", tostring(result)) end
        return begin("close_dialog", function(_, failure)
            if not failure then end_modal({ status = "selected", value = result })
            elseif options.logger then pcall(options.logger, "close_dialog_failed", failure.message) end
        end, function(finish) adapter:back(finish) end)
    end
    function self:dispose()
        if self.disposed then return end
        self.disposed = true
        local pending = self.pending
        self.pending = nil
        if pending then notify(pending.done, nil, error_value("cancelled")) end
        end_modal({ status = "cancelled" })
        if adapter.dispose then adapter:dispose() end
    end
    return self
end
return M
