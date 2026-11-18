-- Save manager tests: new archive, migration, corrupt, future version, write
-- failure, dual-slot recovery, slot grouping, read-failure semantics and the
-- not-loaded commit guard. Uses the in-memory storage adapter.
package.path = "./?.lua;./?/init.lua;../?.lua;../?/init.lua;" .. package.path

local T = require "tests.lua.harness"
local Save = require "framework.save.save_manager"
local Storage = require "framework.save.storage"

local function make_save(opts)
    local storage = Storage.memory()
    return Save.create(storage, opts), storage
end

-- 1. First run uses defaults, meta.source == "default".
T.run("first run uses defaults", function()
    local save = make_save({ defaults = function() return { gold = 100 } end })
    local snapshot, meta = save:load()
    T.assert_truthy(meta, "meta")
    T.assert_eq(meta.source, "default")
    T.assert_eq(snapshot.gold, 100)
end)

-- 2. Commit then reload returns the same payload (default slot "default").
T.run("commit then load round-trips", function()
    local save = make_save({ defaults = function() return {} end })
    save:load() -- mark loaded
    local rev = save:commit(nil, { gold = 42 })
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
    local save, storage = make_save({ migrations = migrations, current_version = 3 })
    storage.store.default_primary = { schema_version = 1, revision = 1, saved_at = 0, payload = { gold = 10 } }
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
    local save, storage = make_save({ migrations = migrations, current_version = 2 })
    storage.store.default_primary = { schema_version = 1, revision = 1, saved_at = 0, payload = { gold = 10 } }
    local snapshot, meta, err = save:load()
    T.assert_nil(snapshot, "snapshot on failure")
    T.assert_eq(err.code, "migration_failed")
    -- Archive untouched.
    T.assert_eq(storage.store.default_primary.payload.gold, 10)
end)

-- 5. Corrupt envelope returns error.
T.run("corrupt envelope errors", function()
    local save, storage = make_save({})
    storage.store.default_primary = { not_an_envelope = true }
    local snapshot, meta, err = save:load()
    T.assert_nil(snapshot)
    T.assert_eq(err.code, "corrupt")
end)

-- 6. Future version returns error.
T.run("future version errors", function()
    local save, storage = make_save({})
    storage.store.default_primary = { schema_version = 99, revision = 1, saved_at = 0, payload = {} }
    local snapshot, meta, err = save:load()
    T.assert_nil(snapshot)
    T.assert_eq(err.code, "future_version")
end)

-- 7. Write failure does not report success.
T.run("write failure reports error", function()
    local save, storage = make_save({})
    save:load()
    storage.fail_write = true
    local rev, err = save:commit(nil, { gold = 1 })
    T.assert_nil(rev, "revision on failure")
    T.assert_truthy(err, "error")
end)

-- 8. Dual-slot: truncated backup is ignored when primary is healthy.
T.run("dual-slot prefers healthy primary over truncated backup", function()
    local save, storage = make_save({})
    storage.store.default_primary = { schema_version = 1, revision = 5, saved_at = 0, payload = { gold = 100 } }
    storage.store.default_backup = { schema_version = 1, revision = 4 } -- missing payload -> invalid
    local snapshot, meta, err = save:load()
    T.assert_nil(err, "no error")
    T.assert_eq(snapshot.gold, 100)
    T.assert_eq(meta.revision, 5)
end)

-- 9. Dual-slot: primary corrupt, backup healthy -> recover from backup.
T.run("dual-slot recovers from backup when primary corrupt", function()
    local save, storage = make_save({})
    storage.store.default_primary = { garbage = true } -- corrupt
    storage.store.default_backup = { schema_version = 1, revision = 3, saved_at = 0, payload = { gold = 77 } }
    local snapshot, meta, err = save:load()
    T.assert_nil(err, "no error")
    T.assert_eq(snapshot.gold, 77)
    T.assert_eq(meta.source, "archive")
end)

-- 10. Validation rejects invalid payload.
T.run("validate rejects invalid payload", function()
    local save, storage = make_save({ validate = function(p) return p.gold >= 0, "negative gold" end })
    storage.store.default_primary = { schema_version = 1, revision = 1, saved_at = 0, payload = { gold = -5 } }
    local snapshot, meta, err = save:load()
    T.assert_nil(snapshot)
    T.assert_eq(err.code, "invalid")
end)

-- 11. load returns a copy (mutating snapshot does not corrupt cache/archive).
T.run("load returns a defensive copy", function()
    local save = make_save({ defaults = function() return {} end })
    save:load()
    save:commit(nil, { gold = 10 })
    local snapshot = save:load()
    snapshot.gold = 999
    local again = save:load()
    T.assert_eq(again.gold, 10)
end)

-- 12. revision increments monotonically.
T.run("revision increments", function()
    local save = make_save({})
    save:load()
    local r1 = save:commit(nil, {})
    local r2 = save:commit(nil, {})
    T.assert_truthy(r2 > r1, "revision monotonic")
end)

-- 13. Slots are truly independent: two logical saves never overwrite each other.
T.run("slots are independent groups", function()
    local save = make_save({ defaults = function() return {} end })
    save:load("game")
    save:load("settings")
    save:commit("game", { gold = 7 })
    save:commit("settings", { muted = true })
    local game = save:load("game")
    local settings = save:load("settings")
    T.assert_eq(game.gold, 7)
    T.assert_truthy(settings.muted == true, "settings muted")
    local snapshot = save:load("game")
    T.assert_eq(snapshot.gold, 7)
end)

-- 14. A hard storage read failure is NOT a first run: load returns an error.
T.run("read failure surfaces an error instead of defaults", function()
    local save, storage = make_save({ defaults = function() return { gold = 1 } end })
    storage.fail_read = true
    local snapshot, meta, err = save:load()
    T.assert_nil(snapshot, "no snapshot on read failure")
    T.assert_truthy(err, "error surfaced")
    T.assert_eq(err.code, "read_failed")
end)

-- 15. commit before a successful load is refused (guard against clobbering).
T.run("commit refuses before load", function()
    local save = make_save({ defaults = function() return {} end })
    local rev, err = save:commit(nil, { gold = 1 })
    T.assert_nil(rev)
    T.assert_eq(err.code, "not_loaded")
end)

-- 16. After a FAILED load, commit is still refused — defaults must not be able
-- to overwrite the real archive.
T.run("commit refuses after failed load", function()
    local save, storage = make_save({ defaults = function() return { gold = 1 } end })
    storage.store.default_primary = { schema_version = 1, revision = 1, saved_at = 0, payload = { gold = 500 } }
    storage.fail_read = true
    local snapshot, meta, err = save:load()
    T.assert_nil(snapshot)
    storage.fail_read = false
    local rev, cerr = save:commit(nil, { gold = 1 })
    T.assert_nil(rev, "no revision")
    T.assert_eq(cerr.code, "not_loaded")
    -- Archive payload intact.
    T.assert_eq(storage.store.default_primary.payload.gold, 500)
end)

-- 17. One hard error + one healthy slot: healthy slot wins, error is suppressed.
T.run("healthy slot wins over failed sibling slot", function()
    local save, storage = make_save({})
    storage.store.default_primary = { schema_version = 1, revision = 2, saved_at = 0, payload = { gold = 9 } }
    storage.fail_read_backup = nil
    -- Simulate backup read failure by replacing the adapter read only for backup.
    local original_read = storage.read
    storage.read = function(slot)
        if slot == "default_backup" then return nil, { code = "read_failed", message = "injected" } end
        return original_read(slot)
    end
    local snapshot, meta, err = save:load()
    T.assert_nil(err, "primary healthy wins")
    T.assert_eq(snapshot.gold, 9)
end)

-- 18. Both slots hard-fail: error surfaced, not defaults.
T.run("both slots failing hard is an error", function()
    local save, storage = make_save({ defaults = function() return { gold = 1 } end })
    storage.fail_read = true
    local snapshot, meta, err = save:load()
    T.assert_nil(snapshot)
    T.assert_truthy(err, "error")
end)

-- 19. mark_loaded allows creating a slot explicitly without reading it.
T.run("mark_loaded enables first commit", function()
    local save = make_save({})
    save:mark_loaded("fresh")
    local rev, err = save:commit("fresh", { a = 1 })
    T.assert_truthy(rev, "revision")
    T.assert_nil(err, "no error")
end)

os.exit(T.summary() == 0 and 0 or 1)
