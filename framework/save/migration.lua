-- Migration helpers. The framework migrates the envelope; the game provides
-- payload migrations and a validate function.
--
-- A migration chain maps source schema_version -> function(copy) -> copy,
-- where `copy` is the payload (a deep copy of the original). Migrations MUST
-- run one level at a time, validating each step, and only commit a new envelope
-- after every step succeeds. A failed migration must never overwrite the
-- existing archive.

local M = {}

-- Run `migrations` (a table keyed by source version, e.g. { [1] = fn_1_to_2,
-- [2] = fn_2_to_3 }) from `from_version` to `to_version`, applying each step to
-- a copy of `payload`. Returns the migrated payload and the versions traversed,
-- or nil, error if any step fails or a required step is missing.
function M.run(migrations, payload, from_version, to_version)
    if from_version == to_version then return payload, {} end
    local current = from_version
    local value = payload
    local path = {}
    while current ~= to_version do
        local step = migrations[current]
        if not step then
            return nil, { code = "migration_missing", message = "no migration from version " .. tostring(current) }
        end
        local ok, result = pcall(step, value)
        if not ok then
            return nil, { code = "migration_failed", message = "migration from " .. tostring(current) .. " failed: " .. tostring(result) }
        end
        value = result
        path[#path + 1] = current
        current = current + 1
        -- Guard against a migration that jumps the wrong direction.
        if current < from_version then
            return nil, { code = "migration_invalid", message = "migration moved backwards" }
        end
    end
    return value, path
end

-- Produce the deep-ish copy used before mutating a payload during migration.
-- Only plain serializable data is expected (no functions/userdata/urls).
local function copy(value, seen)
    seen = seen or {}
    if type(value) ~= "table" then return value end
    if seen[value] then return seen[value] end
    local out = {}
    seen[value] = out
    for k, v in pairs(value) do out[copy(k, seen)] = copy(v, seen) end
    return out
end
M.copy = copy

return M
