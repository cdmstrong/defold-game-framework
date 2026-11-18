local Screen = require "framework.ui.screen"
local Theme = require "framework.ui.theme"
local Button = require "framework.ui.components.button"
local ProgressBar = require "framework.ui.components.progress_bar"
local CurrencyBar = require "framework.ui.components.currency_bar"
local ItemCard = require "framework.ui.components.item_card"
local Tab = require "framework.ui.components.tab"
local Scroll = require "framework.ui.components.scroll"
local Toast = require "framework.ui.components.toast"
local context = require "examples.ui_demo.context"
local M = {}
local function send(message, data) msg.post("main:/bootstrap#script", message, data or {}) end

-- Node id -> theme token bindings. Every themed node is listed here so a theme
-- switch recolors the whole screen without rebuilding business state.
local THEME_BINDINGS = {
    background = "background",
    surface = "surface",
    card = "surface_alt",
    scroll_content = "surface_alt",
    toast = "surface_alt",
    btn_section = "text_dim",
    prog_section = "text_dim",
    curr_section = "text_dim",
    card_section = "text_dim",
    tab_section = "text_dim",
    scroll_section = "text_dim",
    title = "text",
    card_title = "text",
    scroll_item_1 = "text",
    scroll_item_2 = "text",
    scroll_item_3 = "text",
    card_subtitle = "text_dim",
    status = "text_dim",
    pause_status = "text_dim",
}

local function apply_theme(theme)
    local t = Theme.validate(theme)
    for node_id, token in pairs(THEME_BINDINGS) do
        local ok, node = pcall(gui.get_node, node_id)
        if ok and node then gui.set_color(node, t[token]) end
    end
end

function M.init(self, id)
    self.id, self.alive = id, true
    self.screen = Screen.create(id, { context = self })
    local druid = self.screen.druid
    local function button(node, fn) return druid:new_button(node, fn) end

    self.components = {}

    if id == "home" then
        button("components", function() send("navigate", { route = "components" }) end)
        button("settings", function() send("navigate", { route = "settings" }) end)
        button("dialog", function() send("dialog") end)
    elseif id == "components" then
        -- Button (normal + disabled)
        self.components.count_btn = Button.create(druid, { trigger = "count", label = "count_label" }, { on_click = function() send("count") end })
        self.components.disabled_btn = Button.create(druid, { trigger = "disabled", label = "disabled_label" }, {})
        self.components.disabled_btn:set_enabled(false)

        -- ProgressBar
        self.components.progress = ProgressBar.create(druid, { fill = "progress_fill" }, { min = 0, max = 100, initial = 0.65 })

        -- CurrencyBar
        self.components.currency = CurrencyBar.create(druid, { value = "currency_value" }, { symbol = "¥" })
        self.components.currency:set_value(12345)

        -- ItemCard
        self.components.card = ItemCard.create(druid, { title = "card_title", subtitle = "card_subtitle", price = "card_price", trigger = "card" }, { on_select = function()
            if self.components.toast then self.components.toast:show("Card selected") end
        end })
        self.components.card:set_title("Copper Ore")
        self.components.card:set_subtitle("Basic material")
        self.components.card:set_price("¥2 / unit")

        -- Tab
        self.components.tab = Tab.create(druid, { tabs = {
            { trigger = "tab_a", active_marker = "tab_a_mark" },
            { trigger = "tab_b", active_marker = "tab_b_mark" },
            { trigger = "tab_c", active_marker = "tab_c_mark" },
        } }, { on_change = function(_, i) send("tab", { index = i }) end })
        self.components.tab:set_active(1)

        -- Scroll
        self.components.scroll = Scroll.create(druid, { view = "scroll_view", content = "scroll_content" })

        -- Toast
        self.components.toast = Toast.create(druid, { root = "toast", text = "toast_text" }, { duration = 2.0 })

        button("theme", function() send("theme") end)
        button("ad", function() send("ad") end)
        button("settings", function() send("navigate", { route = "settings" }) end)
        button("back", function() send("back") end)
    elseif id == "settings" then
        button("vol_music_minus", function() send("volume_down", { group = "music" }) end)
        button("vol_music_plus", function() send("volume_up", { group = "music" }) end)
        button("vol_sfx_minus", function() send("volume_down", { group = "sfx" }) end)
        button("vol_sfx_plus", function() send("volume_up", { group = "sfx" }) end)
        button("mute", function() send("mute") end)
        button("locale", function() send("locale") end)
        button("pause", function() send("pause") end)
        button("dialog", function() send("dialog") end)
        button("back", function() send("back") end)
    else
        button("confirm", function() send("confirm") end)
        button("cancel", function() send("back") end)
    end

    local url = msg.url()
    self.unsubscribe = context.bus:subscribe("changed", function()
        if self.alive then msg.post(url, "refresh") end
    end)
    context.views[id] = true
    M.refresh(self)
    print("M1_VIEW_INIT " .. id)
end

function M.refresh(self)
    local state = "Clicks " .. context.clicks .. "    |    Active seconds " .. context.ticks
    gui.set_text(gui.get_node("status"), state)
    gui.set_text(gui.get_node("pause_status"), context.pause:is_paused() and "Simulation paused" or "Simulation running")
    if self.id == "components" then
        local p = self.components.progress
        if p then p:set_value(35 + (context.clicks % 70)) end
        local theme_label = gui.get_node("theme_label")
        if theme_label then gui.set_text(theme_label, "Theme: " .. context.theme) end
    elseif self.id == "settings" then
        local l = context.l10n
        -- Localized labels.
        local title = gui.get_node("title")
        if title then gui.set_text(title, l:t("settings_title")) end
        local mute_label = gui.get_node("mute_label")
        if mute_label then gui.set_text(mute_label, context.settings:get("muted") and l:t("unmute") or l:t("mute")) end
        local locale_label = gui.get_node("locale_label")
        if locale_label then gui.set_text(locale_label, l:t("language") .. ": " .. (context.locale == "zh" and l:t("locale_zh") or l:t("locale_en"))) end
        -- Volume values.
        local mv = gui.get_node("vol_music_value")
        if mv then gui.set_text(mv, math.floor(context.settings:get("volume_music") * 100 + 0.5) .. "%") end
        local sv = gui.get_node("vol_sfx_value")
        if sv then gui.set_text(sv, math.floor(context.settings:get("volume_sfx") * 100 + 0.5) .. "%") end
        local vol_music_label = gui.get_node("vol_music_label")
        if vol_music_label then gui.set_text(vol_music_label, l:t("volume_music")) end
        local vol_sfx_label = gui.get_node("vol_sfx_label")
        if vol_sfx_label then gui.set_text(vol_sfx_label, l:t("volume_sfx")) end
        local back_label = gui.get_node("back_label")
        if back_label then gui.set_text(back_label, l:t("back")) end
    end
    apply_theme(context.theme)
end

function M.update(self, dt)
    self.screen:update(dt)
    if self.components and self.components.toast then self.components.toast:update(dt) end
end

function M.input(self, action_id, action)
    if context.ui:is_busy() then return true end
    if (action_id == hash("key_esc") or action_id == hash("key_back")) and action.pressed then
        send("back"); return true
    end
    return self.screen.druid:on_input(action_id, action) or self.id == "dialog"
end

function M.message(self, message_id, message, sender)
    if message_id == hash("refresh") then M.refresh(self) end
    self.screen:on_message(message_id, message, sender)
end

function M.final(self)
    self.alive = false
    self.unsubscribe()
    self.screen:dispose()
    context.views[self.id] = nil
    print("M1_VIEW_FINAL " .. self.id)
end
return M
