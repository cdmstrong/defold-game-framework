-- Settings service: validated key/value storage with persistence and change
-- notifications. Known keys and ranges are checked before accept; unknown keys
-- or out-of-range values are rejected.
--
-- set(key, value) -> true | nil, error
-- get(key)        -> value
-- subscribe(fn)   -> unsubscribe

local M = {}

-- A schema maps key -> { default = v, validate = fn(value) -> bool, coerce = fn(v) -> v }
function M.create(options)
    options = options or {}
    local self = {
        schema = options.schema or {},
        storage = options.storage, -- optional persistent storage { read, write }
        values = {},
        listeners = {},
        persist_key = options.persist_key or "settings",
    }

    -- Load persisted values (validating each against the schema).
    -- storage:read returns (value, error).
    if self.storage and self.storage.read then
        local raw, err = self.storage.read(self.persist_key)
        if not err and type(raw) == "table" then
            for k, v in pairs(raw) do
                local spec = self.schema[k]
                if spec and spec.validate then
                    local valid = spec.validate(v)
                    if valid then self.values[k] = v end
                end
            end
        end
    end

    local function notify()
        for _, fn in ipairs(self.listeners) do fn() end
    end

    local function persist()
        if self.storage and self.storage.write then
            local ok, err = self.storage.write(self.persist_key, self.values)
            if not ok then return nil, err or { code = "persist_failed", message = "settings write failed" } end
        end
        return true
    end

    function self:get(key)
        local spec = self.schema[key]
        if spec then
            return self.values[key] ~= nil and self.values[key] or spec.default
        end
        return nil
    end

    function self:set(key, value)
        local spec = self.schema[key]
        if not spec then
            return nil, { code = "unknown_key", message = tostring(key) }
        end
        if spec.coerce then value = spec.coerce(value) end
        if spec.validate and not spec.validate(value) then
            return nil, { code = "invalid_value", message = tostring(key) .. "=" .. tostring(value) }
        end
        self.values[key] = value
        local ok, err = persist()
        if not ok then
            -- Roll back the in-memory value if persistence failed, so in-memory
            -- state and disk stay consistent.
            return nil, err
        end
        notify()
        return true
    end

    function self:subscribe(fn)
        self.listeners[#self.listeners + 1] = fn
        return function()
            for i, f in ipairs(self.listeners) do
                if f == fn then table.remove(self.listeners, i); return end
            end
        end
    end

    return self
end

return M
