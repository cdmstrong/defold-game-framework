-- Localization service: locale switching and message lookup with fallback.
--
-- Fallback order: selected locale -> default locale -> "[key]". Missing keys are
-- logged. Named-parameter interpolation is supported (no full ICU).
--
-- set_locale(locale) -> true | nil, error
-- t(key, params)     -> string

local M = {}

function M.create(options)
    options = options or {}
    local self = {
        messages = options.messages or {}, -- messages[locale][key] = "string"
        default_locale = options.default_locale or "en",
        locale = options.locale or options.default_locale or "en",
        logger = options.logger or function(topic, detail) end,
        fallback_literal = options.fallback_literal ~= false, -- fall back to "[key]" by default
    }

    function self:set_locale(locale)
        if type(locale) ~= "string" or locale == "" then
            return nil, { code = "invalid_locale", message = tostring(locale) }
        end
        self.locale = locale
        return true
    end

    function self:get_locale()
        return self.locale
    end

    local function interpolate(template, params)
        if not params then return template end
        local out = template
        for k, v in pairs(params) do
            out = out:gsub("{" .. k .. "}", tostring(v))
        end
        return out
    end

    function self:t(key, params)
        local candidates = { self.locale, self.default_locale }
        for _, locale in ipairs(candidates) do
            local table_for_locale = self.messages[locale]
            if table_for_locale and table_for_locale[key] ~= nil then
                return interpolate(table_for_locale[key], params)
            end
        end
        self.logger("localization_missing", key)
        if self.fallback_literal then
            return "[" .. key .. "]"
        end
        return key
    end

    -- Convenience: does a locale table exist (for capability checks)?
    function self:has_locale(locale)
        return self.messages[locale] ~= nil
    end

    return self
end

return M
