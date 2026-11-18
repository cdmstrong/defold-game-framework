-- Display-only economy header for tycoon games. Game chooses the currency name.
local CurrencyBar = require "framework.ui.components.currency_bar"
local M = {}
function M.format_amount(value)
    assert(type(value) == "number" and value == value, "finite amount required")
    local digits = tostring(math.floor(value))
    local sign = ""
    if digits:sub(1, 1) == "-" then sign, digits = "-", digits:sub(2) end
    return sign .. digits:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "")
end
function M.create(druid, nodes, options)
    options = options or {}
    local bar = CurrencyBar.create(druid, { value = nodes.value }, { format = options.format or M.format_amount })
    local income = nodes.income and gui.get_node(nodes.income)
    function bar:set_income(value, suffix)
        if income then gui.set_text(income, (options.format or M.format_amount)(value) .. (suffix or " /s")) end
    end
    return bar
end
return M
