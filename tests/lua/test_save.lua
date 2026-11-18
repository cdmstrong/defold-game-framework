-- Save manager tests: new archive, migration, corrupt, future version, write
-- failure, dual-slot truncated recovery. Uses the in-memory storage adapter.
package.path = "./?.lua;./?/init.lua;../?.lua;../?/init.lua;" .. package.path

local T = require "tests.lua.harness"
local Save = require "framework.save.save_manager"
local Storage = require "framework.save.storage"

local function make_save(opts)
    local storage = Storage.memory()
    return Save.create(storage, opts)
end

-- 1. First run uses defaults, meta.source == "default".
T.run("first run uses defaults", function()
    local save = make_save({ defaults = function() return { gold = 100 } end })
    local snapshot, meta = save:load()
    T.assert_truthy(meta, "meta")
    T.assert_eq(meta.source, "default")
    T.assert_eq(snapshot.gold, 100)
end)

-- 2. Commit then reload returns the same payload.
T.run("commit then load round-trips", function()
    local save = make_save({ defaults = function() return {} end })
    local rev = save:commit("primary", { gold = 42 })
    T.assert_truthy(rev, "revision")
    local snapshot, meta = save:load()
    T.assert_eq(meta.source, "archive")
    T.assert_eq(snapshot.gold, 42)
end)

-- 3. Migration runs level-by-level.
T.run("migration runs 1->3", function()
    local migrations = {
        [1] = function(p) p.gold = p.gold * 2; p.v = 2; return p end,
        [2] = function(p) p.name = "migrated"; p.v = 3; return p end,
    }
    local storage = Storage.memory()
    storage.store.primary = { schema_version = 1, revision = 1, saved_at = 0, payload = { gold = 10 } }
    local save = Save.create(storage, { migrations = migrations, current_version = 3 })
    local snapshot, meta = save:load()
    T.assert_truthy(meta.migrated, "migrated flag")
    T.assert_eq(snapshot.gold, 20)
    T.assert_eq(snapshot.name, "migrated")
    T.assert_eq(snapshot.v, 3)
end)

-- 4. Migration failure returns error and does NOT overwrite the archive.
T.run("migration failure does not overwrite", function()
    local migrations = {
        [1] = function() error("boom") end,
    }
    local storage = Storage.memory()
    storage.store.primary = { schema_version = 1, revision = 1, saved_at = 0, payload = { gold = 10 } }
    local save = Save.create(storage, { migrations = migrations, current_version = 2 })
    local snapshot, meta, err = save:load()
    T.assert_nil(snapshot, "snapshot on failure")
    T.assert_eq(err.code, "migration_failed")
    -- Archive untouched.
    T.assert_eq(storage.store.primary.payload.gold, 10)
end)

-- 5. Corrupt envelope returns error.
T.run("corrupt envelope errors", function()
    local storage = Storage.memory()
    storage.store.primary = { not_an_envelope = true }
    local save = Save.create(storage, {})
    local snapshot, meta, err = save:load()
    T.assert_nil(snapshot)
    T.assert_eq(err.code, "corrupt")
end)

-- 6. Future version returns error.
T.run("future version errors", function()
    local storage = Storage.memory()
    storage.store.primary = { schema_version = 99, revision = 1, saved_at = 0, payload = {} }
    local save = Save.create(storage, {})
    local snapshot, meta, err = save:load()
    T.assert_nil(snapshot)
    T.assert_eq(err.code, "future_version")
end)

-- 7. Write failure does not report success.
T.run("write failure reports error", function()
    local storage = Storage.memory()
    storage.fail_write = true
    local save = Save.create(storage, {})
    local rev, err = save:commit("primary", { gold = 1 })
    T.assert_nil(rev, "revision on failure")
    T.assert_truthy(err, "error")
end)

-- 8. Dual-slot: truncated backup is ignored when primary is healthy.
T.run("dual-slot prefers healthy primary over truncated backup", function()
    local storage = Storage.memory()
    storage.store.primary = { schema_version = 1, revision = 5, saved_at = 0, payload = { gold = 100 } }
    storage.store.backup = { schema_version = 1, revision = 5, payload = {} } -- truncated: missing fields won't pass, but revision equal
    -- Make backup genuinely corrupt/truncated.
    storage.store.backup = { schema_version = 1, revision = 4 } -- missing payload -> invalid
    local save = Save.create(storage, {})
    local snapshot, meta, err = save:load()
    T.assert_nil(err, "no error")
    T.assert_eq(snapshot.gold, 100)
    T.assert_eq(meta.revision, 5)
end)

-- 9. Dual-slot: primary corrupt, backup healthy -> recover from backup.
T.run("dual-slot recovers from backup when primary corrupt", function()
    local storage = Storage.memory()
    storage.store.primary = { garbage = true } -- corrupt
    storage.store.backup = { schema_version = 1, revision = 3, saved_at = 0, payload = { gold = 77 } }
    local save = Save.create(storage, {})
    local snapshot, meta, err = save:load()
    T.assert_nil(err, "no error")
    T.assert_eq(snapshot.gold, 77)
    T.assert_eq(meta.source, "archive")
end)

-- 10. Validation rejects invalid payload.
T.run("validate rejects invalid payload", function()
    local storage = Storage.memory()
    storage.store.primary = { schema_version = 1, revision = 1, saved_at = 0, payload = { gold = -5 } }
    local save = Save.create(storage, { validate = function(p) return p.gold >= 0, "negative gold" end })
    local snapshot, meta, err = save:load()
    T.assert_nil(snapshot)
    T.assert_eq(err.code, "invalid")
end)

-- 11. load returns a copy (mutating snapshot does not corrupt cache/archive).
T.run("load returns a defensive copy", function()
    local save = make_save({ defaults = function() return {} end })
    save:commit("primary", { gold = 10 })
    local snapshot = save:load()
    snapshot.gold = 999
    local again = save:load()
    T.assert_eq(again.gold, 10)
end)

-- 12. revision increments monotonically.
T.run("revision increments", function()
    local save = make_save({})
    local r1 = save:commit("primary", {})
    local r2 = save:commit("primary", {})
    T.assert_truthy(r2 > r1, "revision monotonic")
end)

os.exit(T.summary() == 0 and 0 or 1)
