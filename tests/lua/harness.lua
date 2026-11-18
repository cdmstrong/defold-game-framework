-- Minimal pure-Lua test harness. Runs each test function; any error fails the
-- suite and exits nonzero. No Defold APIs required.
local M = {}

local results = { pass = 0, fail = 0, failures = {} }

function M.assert_eq(actual, expected, label)
    if actual ~= expected then
        error((label or "assert_eq") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual), 2)
    end
end

function M.assert_truthy(value, label)
    if not value then error((label or "assert_truthy") .. ": expected truthy, got " .. tostring(value), 2) end
end

function M.assert_nil(value, label)
    if value ~= nil then error((label or "assert_nil") .. ": expected nil, got " .. tostring(value), 2) end
end

function M.run(name, fn)
    local ok, err = pcall(fn)
    if ok then
        results.pass = results.pass + 1
        print("PASS " .. name)
    else
        results.fail = results.fail + 1
        results.failures[#results.failures + 1] = name .. ": " .. tostring(err)
        print("FAIL " .. name .. ": " .. tostring(err))
    end
end

function M.summary()
    print(string.format("== %d passed, %d failed ==", results.pass, results.fail))
    for _, f in ipairs(results.failures) do print("  " .. f) end
    return results.fail
end

return M
