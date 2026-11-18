-- Storage adapters isolate the Defold save mechanism from the Save manager.
-- An adapter is a plain table with callable functions (dot-call semantics, no
-- implicit self). Adapters MUST be synchronous and report completion truthfully.
--
-- read(slot)           -> envelope | nil, error
--   The (nil, error) channel MUST distinguish two very different cases:
--   * (nil, nil)  = the slot does not exist yet (clean first run)
--   * (nil, err)  = the slot exists but reading it failed (IO error, corrupt
--     payload). Surfacing this as "no data" would make the next save overwrite
--     the real archive with defaults.
-- write(slot, envelope) -> true | nil, error
--
-- The V1 contract only promises synchronous backends; async backends need a
-- separate contract.

local M = {}

-- In-memory adapter for tests and as a reference implementation. It also
-- records write failures when `fail_write` is set, to exercise the manager's
-- "write failure must not report success" path, and read failures when
-- `fail_read` is set.
function M.memory(store)
    store = store or {}
    local self = { store = store }
    function self.read(slot)
        if self.fail_read then
            return nil, { code = "read_failed", message = "injected failure" }
        end
        local raw = store[slot]
        if raw == nil then return nil, nil end
        return raw
    end
    function self.write(slot, envelope)
        if self.fail_write then return nil, { code = "write_failed", message = "injected failure" } end
        store[slot] = envelope
        return true
    end
    return self
end

-- Defold sys.save/sys.load backed adapter. In HTML5 this persists to the
-- browser's IndexedDB, which the integration test exercises across refreshes.
-- Paths MUST come from sys.get_save_file so they are valid per-platform.
function M.defold(sys, options)
    options = options or {}
    local app_id = options.app_id or "framework_demo"
    local self = {}
    local function path(slot)
        return sys.get_save_file(app_id, slot)
    end
    function self.read(slot)
        local ok, data = pcall(sys.load, path(slot))
        if not ok then
            -- pcall failure is a hard IO error, NOT "file absent".
            return nil, { code = "read_failed", message = tostring(data) }
        end
        if data == nil or (type(data) == "table" and not next(data)) then
            -- Absent (sys.load returns nil / an empty table when no file).
            return nil, nil
        end
        if type(data) ~= "table" then
            return nil, { code = "corrupt", message = "unexpected payload type: " .. type(data) }
        end
        return data
    end
    function self.write(slot, envelope)
        local ok, err = sys.save(path(slot), envelope)
        if not ok then return nil, { code = "write_failed", message = tostring(err) } end
        return true
    end
    return self
end

return M
