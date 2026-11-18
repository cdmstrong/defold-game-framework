local M = {}

-- Theme tokens: named roles mapped to colors. Components receive validated colors
-- only; a theme never mutates business state and is applied inside a GUI context.

local THEMES = {
    dark = {
        name = "dark",
        background = vmath.vector4(0.045, 0.06, 0.10, 1),
        surface = vmath.vector4(0.085, 0.115, 0.18, 1),
        surface_alt = vmath.vector4(0.11, 0.15, 0.23, 1),
        text = vmath.vector4(0.85, 0.90, 1, 1),
        text_dim = vmath.vector4(0.50, 0.65, 0.80, 1),
        primary = vmath.vector4(0.18, 0.40, 0.83, 1),
        primary_text = vmath.vector4(0.95, 0.97, 1, 1),
        accent = vmath.vector4(0.98, 0.72, 0.18, 1),
        danger = vmath.vector4(0.83, 0.25, 0.25, 1),
        success = vmath.vector4(0.20, 0.62, 0.35, 1),
        border = vmath.vector4(0.25, 0.33, 0.45, 1),
        overlay = vmath.vector4(0.02, 0.03, 0.05, 0.78),
    },
    light = {
        name = "light",
        background = vmath.vector4(0.94, 0.95, 0.98, 1),
        surface = vmath.vector4(0.99, 0.99, 1, 1),
        surface_alt = vmath.vector4(0.90, 0.92, 0.96, 1),
        text = vmath.vector4(0.10, 0.13, 0.18, 1),
        text_dim = vmath.vector4(0.35, 0.42, 0.52, 1),
        primary = vmath.vector4(0.20, 0.45, 0.90, 1),
        primary_text = vmath.vector4(1, 1, 1, 1),
        accent = vmath.vector4(0.90, 0.58, 0.08, 1),
        danger = vmath.vector4(0.80, 0.20, 0.20, 1),
        success = vmath.vector4(0.15, 0.55, 0.30, 1),
        border = vmath.vector4(0.72, 0.76, 0.84, 1),
        overlay = vmath.vector4(0.05, 0.06, 0.10, 0.45),
    },
}

local REQUIRED = {
    "background", "surface", "surface_alt", "text", "text_dim", "primary",
    "primary_text", "accent", "danger", "success", "border", "overlay",
}

function M.names()
    local out = {}
    for name in pairs(THEMES) do out[#out + 1] = name end
    table.sort(out)
    return out
end

-- Validate a theme token table and return a normalized theme (all tokens resolved).
-- Accepts a preset name string ("dark"/"light") or a full/partial token table.
function M.validate(tokens)
    if type(tokens) == "string" then
        local preset = THEMES[tokens]
        if not preset then return nil, { code = "unknown_theme", message = tostring(tokens) } end
        return preset
    end
    if type(tokens) ~= "table" then return nil, { code = "invalid_theme", message = "theme must be a name or token table" } end
    local base = THEMES[tokens.name] or THEMES.dark
    local theme = { name = tokens.name or base.name }
    for _, key in ipairs(REQUIRED) do
        local value = tokens[key] or base[key]
        if not value then return nil, { code = "invalid_theme", message = "missing token: " .. key } end
        theme[key] = value
    end
    return theme
end

-- Resolve a single token for a theme (falls back to dark preset for unknown keys).
function M.color(theme, key)
    theme = theme or THEMES.dark
    return theme[key] or THEMES.dark[key]
end

-- Apply a theme to a GUI node tree by binding node ids to token roles.
-- bindings maps a node id (string) to a token key (e.g. { background = "surface" }).
-- Must only be called inside the owning GUI context.
function M.apply(root, bindings, theme)
    theme = M.validate(theme)
    for node_id, token in pairs(bindings or {}) do
        local node = gui.get_node(node_id)
        if node then
            gui.set_color(node, theme[token] or THEMES.dark[token] or vmath.vector4(1, 1, 1, 1))
        end
    end
    return theme
end

return M
