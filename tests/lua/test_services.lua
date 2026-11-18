-- Settings + Localization + Audio tests (pure Lua).
package.path = "./?.lua;./?/init.lua;../?.lua;../?/init.lua;" .. package.path

local T = require "tests.lua.harness"
local Settings = require "framework.services.settings"
local L10n = require "framework.data.localization"
local Audio = require "framework.services.audio"

-- Settings -------------------------------------------------------------------
T.run("settings defaults and get", function()
    local s = Settings.create({ schema = { volume = { default = 0.8, validate = function(v) return v >= 0 and v <= 1 end } } })
    T.assert_eq(s:get("volume"), 0.8)
end)

T.run("settings rejects unknown key", function()
    local s = Settings.create({ schema = {} })
    local ok, err = s:set("nope", 1)
    T.assert_nil(ok)
    T.assert_eq(err.code, "unknown_key")
end)

T.run("settings rejects out-of-range", function()
    local s = Settings.create({ schema = { volume = { default = 0.8, validate = function(v) return v >= 0 and v <= 1 end } } })
    local ok, err = s:set("volume", 5)
    T.assert_nil(ok)
    T.assert_eq(err.code, "invalid_value")
end)

T.run("settings persists and reloads", function()
    local store = {}
    local backend = {
        read = function(k) return store[k], nil end,
        write = function(k, v) store[k] = v; return true end,
    }
    local s1 = Settings.create({ schema = { volume = { default = 0.8, validate = function(v) return v >= 0 and v <= 1 end } }, storage = backend })
    T.assert_truthy(s1:set("volume", 0.3))
    -- New instance reads persisted value.
    local s2 = Settings.create({ schema = { volume = { default = 0.8, validate = function(v) return v >= 0 and v <= 1 end } }, storage = backend })
    T.assert_eq(s2:get("volume"), 0.3)
end)

T.run("settings notifies subscribers", function()
    local s = Settings.create({ schema = { volume = { default = 0.8, validate = function(v) return v >= 0 and v <= 1 end } } })
    local called = false
    s:subscribe(function() called = true end)
    s:set("volume", 0.5)
    T.assert_truthy(called, "subscriber called")
end)

-- Localization ---------------------------------------------------------------
local messages = {
    en = { hello = "Hello, {name}!", missing_zh = "only english" },
    zh = { hello = "你好，{name}！" },
}

T.run("localization resolves current locale", function()
    local l = L10n.create({ messages = messages, default_locale = "en", locale = "zh" })
    T.assert_eq(l:t("hello", { name = "World" }), "你好，World！")
end)

T.run("localization falls back to default locale", function()
    local l = L10n.create({ messages = messages, default_locale = "en", locale = "zh" })
    T.assert_eq(l:t("missing_zh"), "only english")
end)

T.run("localization falls back to [key]", function()
    local logged = {}
    local l = L10n.create({ messages = messages, default_locale = "en", locale = "zh", logger = function(t, d) logged[#logged+1] = d end })
    T.assert_eq(l:t("does_not_exist"), "[does_not_exist]")
    T.assert_eq(#logged, 1, "missing key logged")
end)

T.run("localization rejects invalid locale", function()
    local l = L10n.create({ messages = messages })
    local ok, err = l:set_locale("")
    T.assert_nil(ok)
    T.assert_eq(err.code, "invalid_locale")
end)

-- Audio ----------------------------------------------------------------------
T.run("audio holds music until unlock", function()
    local played = {}
    local backend = { play = function(id, opts) played[#played+1] = id; return id end }
    local a = Audio.create(backend, {})
    a:play_music("theme")
    T.assert_eq(#played, 0, "no play before unlock")
    a:unlock()
    T.assert_eq(#played, 1, "played after unlock")
    T.assert_eq(played[1], "theme")
end)

T.run("audio sfx before unlock errors", function()
    local a = Audio.create({}, {})
    local ok, err = a:play_sfx("click")
    T.assert_nil(ok)
    T.assert_eq(err.code, "not_unlocked")
end)

T.run("audio volume clamps and validates group", function()
    local a = Audio.create({}, {})
    T.assert_truthy(a:set_volume("music", 0.5))
    T.assert_eq(a:get_volume("music"), 0.5)
    a:set_volume("music", 99)
    T.assert_eq(a:get_volume("music"), 1.0)
    local ok, err = a:set_volume("bogus", 0.5)
    T.assert_nil(ok)
    T.assert_eq(err.code, "unknown_group")
end)

T.run("audio mute zeroes effective gain", function()
    local a = Audio.create({}, {})
    a:unlock()
    a:set_muted(true)
    T.assert_truthy(a:is_muted())
end)

os.exit(T.summary() == 0 and 0 or 1)
