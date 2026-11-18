# Tycoon UI kit (0.1.0)

This is the genre layer. It imports `framework.ui.components` and never imports `examples.*` or a game's rules. A consumer needs both the base framework library and this library.

- `currency_header.gui` is an editable Defold GUI template with `value` and `income` nodes. Add a `TYPE_TEMPLATE` node in a screen GUI with `template: "/game_modules/tycoon/ui/currency_header.gui"`. Defold prefixes the runtime nodes with the template node ID, e.g. `economy/value` and `economy/income`.
- `currency_header.lua` binds the value and optional income nodes. Supply a custom formatter or use comma-separated integer display.
- `upgrade_list.lua` binds any number of upgrade rows to labels, enabled state, and game-supplied callbacks. It owns no currency or upgrade state.

The miner example uses both bindings and instantiates the GUI template on its mining screen. The colors, fonts, and text in the example's other GUI files are still game-specific. `shop.gui` and `upgrade.gui` remain local until shared layouts are validated with a second tycoon game.

```lua
local Header = require "game_modules.tycoon.ui.currency_header"
local UpgradeList = require "game_modules.tycoon.ui.upgrade_list"
local header = Header.create(druid, { value = "economy/value", income = "economy/income" })
header:set_value(12500)
header:set_income(42)
local upgrades = UpgradeList.create(druid, {
  { id = "speed", trigger = "speed_button", label = "speed_label", on_select = function() end },
})
upgrades:set_row("speed", { title = "Speed", level = 2, cost = Header.format_amount(1000), enabled = true })
```

The Defold GUI template does not carry its own script into the host GUI. Call the binding module from the host GUI script. Fonts or textures added later must live inside the type library, the base library, or builtins, so exported resources stay complete.
