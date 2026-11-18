local M = {}
local function failure(code, detail) return { code = code, message = tostring(detail) } end
function M.create(config, adapters)
    config, adapters = config or {}, adapters or {}
    local self = { state = "created", services = {}, started = {} }
    local definitions, names = config.services or {}, {}
    for _, spec in ipairs(definitions) do
        assert(type(spec.name) == "string" and type(spec.create) == "function", "invalid service")
        assert(not names[spec.name], "duplicate service: " .. spec.name)
        names[spec.name] = true
    end
    function self:shutdown()
        if self.state == "stopped" then return true end
        self.state = "stopped"
        local first_error
        for i = #self.started, 1, -1 do
            local service = self.started[i]
            if service.shutdown then
                local ok, err = pcall(service.shutdown, service)
                if not ok then first_error = first_error or failure("shutdown_failed", err) end
            end
        end
        self.started, self.services = {}, {}
        if first_error then return nil, first_error end
        return true
    end
    function self:start()
        if self.state == "running" then return true end
        if self.state ~= "created" then return nil, failure("invalid_state", self.state) end
        self.state = "starting"
        for _, spec in ipairs(definitions) do
            local ok, service = pcall(spec.create, adapters, self)
            if not ok or type(service) ~= "table" then
                self:shutdown()
                return nil, failure("service_create_failed", service)
            end
            self.services[spec.name] = service
            self.started[#self.started + 1] = service
            if service.start then
                local called, result, err = pcall(service.start, service)
                if not called or result ~= true then
                    self:shutdown()
                    return nil, failure("service_start_failed", err or result)
                end
            end
        end
        self.state = "running"
        return true
    end
    function self:service(name)
        if not self.services[name] then return nil, failure("unknown_service", name) end
        return self.services[name]
    end
    function self:update(dt)
        if self.state ~= "running" then return nil, failure("invalid_state", self.state) end
        for _, service in ipairs(self.started) do
            if service.update then
                local ok, err = pcall(service.update, service, dt)
                if not ok then return nil, failure("service_update_failed", err) end
            end
        end
        return true
    end
    return self
end
return M
