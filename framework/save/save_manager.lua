-- Save manager: envelope handling, per-slot primary/backup pairs, migration,
-- validation and recovery. The framework manages the envelope; the game
-- supplies payload migrations and a validate function.
--
-- envelope = { schema_version = n, revision = n, saved_at = t, payload = {} }
--
-- Slot semantics (V2):
--   * One manager instance manages MANY independent logical saves.
--   * load(slot) / commit(slot, ...) take a logical save name ("game",
--     "settings", ...). Each logical save owns its own physical
--     "<slot>_primary" / "<slot>_backup" pair, so two saves never overwrite
--     each other. Omitted slot defaults to "default".
--   * revision / cache / load-state are tracked per slot.
--
-- Failure semantics:
--   * load returns (snapshot, meta, err). err ~= nil means "do not continue
--     with defaults": storage read failure, corrupt envelope, future version
--     or failed migration are all surfaced explicitly.
--   * A slot where BOTH physical reads fail hard is an error, NOT a first
--     run. Only (nil, nil) from storage (file absent) means first run.
--   * commit refuses to write to a slot until load(slot) succeeded. This
--     prevents a failed-load session from clobbering the real archive with
--     defaults.
--   * A write failure never reports success.

local Migration = require "framework.save.migration"

local M = {}

local CURRENT_VERSION = 1 -- framework envelope schema version
local DEFAULT_SLOT = "default"
local PRIMARY_SUFFIX = "_primary"
local BACKUP_SUFFIX = "_backup"

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
        migrations = options.migrations or {},
        validate = options.validate,
        defaults = options.defaults or function() return {} end,
        clock = options.clock,
        current_version = options.current_version or CURRENT_VERSION,
    }
    self.cache = {} -- logical slot -> loaded snapshot
    self.loaded = {} -- logical slot -> true once load(slot) succeeded
    self.revisions = {} -- logical slot -> next revision number

    local function slot_revision(slot)
        self.revisions[slot] = self.revisions[slot] or 0
        return self.revisions[slot]
    end

    -- Read one physical slot. storage:read returns (envelope, error):
    -- (nil, nil) = absent, (nil, err) = hard read failure, (env, nil) = ok.
    local function read_raw(physical)
        local envelope, err = self.storage.read(physical)
        if err then
            return nil, err
        end
        return envelope, nil
    end

    -- Pick the valid, newest envelope among the slot's primary and backup.
    -- A corrupt or future-version slot is skipped only if the other slot is
    -- healthy. If nothing usable is found, the first hard error is surfaced —
    -- never silently treated as a first run.
    local function read_best(slot)
        local primary, primary_err = read_raw(slot .. PRIMARY_SUFFIX)
        local backup, backup_err = read_raw(slot .. BACKUP_SUFFIX)
        if primary == nil and backup == nil then
            -- Both absent: first run only when neither read failed.
            if primary_err or backup_err then
                return nil, primary_err or backup_err
            end
            return nil, nil
        end

        local best, best_err
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
            elseif candidate.err then
                -- One hard failure while the other slot may still be usable.
                best_err = best_err or candidate.err
            end
        end
        if best == nil then return nil, best_err or { code = "corrupt", message = "no usable envelope" } end
        return best, nil
    end

    -- load: read the best slot, migrate, validate, return a snapshot copy.
    -- Returns (snapshot, meta, err); snapshot is nil when err ~= nil.
    function self:load(slot, defaults, migrations, validate)
        slot = slot or DEFAULT_SLOT
        defaults = defaults or self.defaults
        migrations = migrations or self.migrations
        validate = validate or self.validate

        local envelope, err = read_best(slot)
        if err then
            return nil, nil, err
        end

        local meta = { source = "default", migrated = false, revision = 0, slot = slot }

        if envelope == nil then
            local snapshot = type(defaults) == "function" and defaults() or (defaults or {})
            self.cache[slot] = snapshot
            self.loaded[slot] = true
            self.revisions[slot] = math.max(slot_revision(slot), 0)
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
        self.revisions[slot] = math.max(slot_revision(slot), envelope.revision or 0)
        local snapshot = Migration.copy(payload)
        self.cache[slot] = snapshot
        self.loaded[slot] = true
        return snapshot, meta, nil
    end

    -- commit: write the slot's primary + backup. Refuses to write until
    -- load(slot) succeeded, so a failed-load session cannot clobber the
    -- real archive with defaults.
    function self:commit(slot, snapshot)
        slot = slot or DEFAULT_SLOT
        if not self.loaded[slot] then
            return nil, { code = "not_loaded", message = "load(" .. tostring(slot) .. ") must succeed before commit" }
        end
        self.revisions[slot] = slot_revision(slot) + 1
        local envelope = {
            schema_version = self.current_version,
            revision = self.revisions[slot],
            saved_at = now(self.clock),
            payload = Migration.copy(snapshot),
        }

        local ok, werr = self.storage.write(slot .. PRIMARY_SUFFIX, envelope)
        if not ok then
            self.revisions[slot] = self.revisions[slot] - 1 -- don't burn a revision on failure
            return nil, werr or { code = "write_failed", message = "primary write failed" }
        end

        -- Backup is best-effort; a backup failure does not fail the commit.
        self.storage.write(slot .. BACKUP_SUFFIX, envelope)

        self.cache[slot] = Migration.copy(snapshot)
        return envelope.revision, nil
    end

    -- Explicitly mark a slot writable without reading it first (e.g. when the
    -- caller knows the slot is fresh and wants to create it).
    function self:mark_loaded(slot)
        self.loaded[slot or DEFAULT_SLOT] = true
    end

    function self:is_loaded(slot)
        return self.loaded[slot or DEFAULT_SLOT] == true
    end

    function self:flush()
        if self.storage.flush then
            return self.storage.flush()
        end
        return true
    end

    function self:dispose()
        self.cache = {}
        self.loaded = {}
        self.revisions = {}
    end

    return self
end

return M
