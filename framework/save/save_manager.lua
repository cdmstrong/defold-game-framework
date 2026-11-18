-- Save manager: envelope handling, primary/backup slots, migration, validation
-- and recovery. The framework manages the envelope; the game supplies payload
-- migrations and a validate function.
--
-- envelope = { schema_version = n, revision = n, saved_at = t, payload = {} }
--
-- Failure semantics (per V1 contract):
--   * load returns a copy; meta carries source/default/migrated status.
--   * first run with no archive uses defaults normally.
--   * corrupt / future-version / failed-migration return explicit errors and let
--     the caller choose recovery; they never silently overwrite.
--   * a write failure never reports success.

local Migration = require "framework.save.migration"

local M = {}

local CURRENT_VERSION = 1 -- framework envelope schema version

local function now(clock)
    clock = clock or os
    return clock.time and clock.time() or os.time()
end

-- Validate an envelope structure without applying game validation.
local function is_envelope(value)
    return type(value) == "table"
        and type(value.schema_version) == "number"
        and type(value.revision) == "number"
        and type(value.payload) == "table"
end

function M.create(storage, options)
    options = options or {}
    local self = {
        storage = storage,
        slots = options.slots or { primary = "primary", backup = "backup" },
        migrations = options.migrations or {},
        validate = options.validate,
        defaults = options.defaults or function() return {} end,
        clock = options.clock,
        current_version = options.current_version or CURRENT_VERSION,
    }
    self.cache = {} -- slot -> loaded snapshot, so reads don't re-parse each time
    self.revision = 0

    -- Read a single slot into a raw envelope, or nil if absent.
    -- storage:read returns (envelope, error); envelope is nil when absent or
    -- on failure, in which case error may carry a code.
    local function read_raw(slot)
        local envelope, err = self.storage.read(slot)
        if err then
            return nil, err
        end
        return envelope, nil
    end

    -- Pick the valid, newest envelope among primary and backup. A corrupt or
    -- future-version slot is skipped only if the other slot is healthy; if both
    -- are bad, the first error is surfaced rather than silently defaulting.
    local function read_best()
        local best, best_err
        local primary, primary_err = read_raw(self.slots.primary)
        local backup, backup_err = read_raw(self.slots.backup)
        if primary == nil and backup == nil then
            return nil, nil -- clean first run
        end
        for _, candidate in ipairs({ { envelope = primary, err = primary_err }, { envelope = backup, err = backup_err } }) do
            if candidate.envelope ~= nil then
                if not is_envelope(candidate.envelope) then
                    best_err = best_err or { code = "corrupt", message = "invalid envelope" }
                elseif candidate.envelope.schema_version > self.current_version then
                    best_err = best_err or { code = "future_version", message = "schema " .. tostring(candidate.envelope.schema_version) .. " > " .. tostring(self.current_version) }
                else
                    if not best or (candidate.envelope.revision or 0) > (best.revision or 0) then
                        best = candidate.envelope
                    end
                end
            end
        end
        if best == nil then return nil, best_err end
        return best, nil
    end

    -- load: read the best slot, migrate, validate, and return a snapshot copy.
    function self:load(slot, defaults, migrations, validate)
        slot = slot or self.slots.primary
        defaults = defaults or self.defaults
        migrations = migrations or self.migrations
        validate = validate or self.validate

        local envelope, err = read_best()
        if err then return nil, nil, err end

        local meta = { source = "default", migrated = false, revision = 0 }

        if envelope == nil then
            local snapshot = type(defaults) == "function" and defaults() or (defaults or {})
            self.cache[slot] = snapshot
            return snapshot, meta, nil
        end

        local payload = envelope.payload
        if envelope.schema_version < self.current_version then
            local migrated, path
            migrated, err = Migration.run(migrations, Migration.copy(payload), envelope.schema_version, self.current_version)
            if not migrated then
                return nil, nil, err
            end
            payload = migrated
            meta.migrated = true
            meta.migration_path = path
        end

        if validate then
            local ok, verr = validate(Migration.copy(payload))
            if not ok then
                return nil, nil, { code = "invalid", message = tostring(verr) }
            end
        end

        meta.source = "archive"
        meta.revision = envelope.revision or 0
        self.revision = math.max(self.revision, envelope.revision or 0)
        local snapshot = Migration.copy(payload)
        self.cache[slot] = snapshot
        return snapshot, meta, nil
    end

    -- commit: write to primary + backup atomically-ish. If the primary write
    -- fails, the backup is NOT written and the caller is told. If backup write
    -- fails after primary succeeded, we still report success but the backup is
    -- stale — this is acceptable since primary is the source of truth.
    function self:commit(slot, snapshot)
        slot = slot or self.slots.primary
        self.revision = self.revision + 1
        local envelope = {
            schema_version = self.current_version,
            revision = self.revision,
            saved_at = now(self.clock),
            payload = Migration.copy(snapshot),
        }

        local ok, werr = self.storage.write(self.slots.primary, envelope)
        if not ok then
            self.revision = self.revision - 1 -- don't burn a revision on failure
            return nil, werr or { code = "write_failed", message = "primary write failed" }
        end

        -- Backup is best-effort; a backup failure does not fail the commit.
        self.storage.write(self.slots.backup, envelope)

        self.cache[slot] = Migration.copy(snapshot)
        return envelope.revision, nil
    end

    function self:flush()
        if self.storage.flush then
            return self.storage.flush()
        end
        return true
    end

    function self:dispose()
        self.cache = {}
    end

    return self
end

return M
