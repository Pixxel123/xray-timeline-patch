-- Adapter for xray-timeline-patch v2. NOT loadable standalone: the build
-- prepends the chunk-locals `Presence` (src/xray_presencemap.lua),
-- `TRANSLATIONS` (src/translations.lua) and `Strip`
-- (src/xray_timeline_strip.lua). tools/build.lua concatenates them.
--
-- The plugin's showTimeline is left alone. The stock EntityListOverlay
-- class is decorated instead: prepareItems gets a character filter, buildUI
-- gets the presence strip under the header, onCloseWidget frees the strip's
-- bitmaps. Every other list screen, and every plugin too old to have the
-- overlay, is untouched.

local UIManager = require("ui/uimanager")
local logger    = require("logger")

local MIN_CHAPTER_COVERAGE = 2 -- a character in fewer chapters is a walk-on
local SETTING = "timeline_presence_map"

local function warn(msg) logger.warn("xray-timeline-patch: " .. msg) end

-- Warnings that would repeat on every rebuild are logged once per session.
local warned = {}
local function warnOnce(key, msg)
    if warned[key] then return end
    warned[key] = true
    warn(msg)
end

-- Resolve the require() prefix for the plugin's own modules at call time.
-- Today plugin dirs sit bare on package.path (pluginloader.lua appends them,
-- so the prefix is ""); the scan keeps working if that ever changes. Lazy
-- because the plugin is not loaded yet when this patch file runs.
local plugin_prefix
local function pluginRequire(mod)
    if plugin_prefix == nil then
        plugin_prefix = ""
        for name in pairs(package.loaded) do
            local p = name:match("^(.*)xray_ui$")
            if p then plugin_prefix = p; break end
        end
    end
    return require(plugin_prefix .. mod)
end

-- Installed only if the plugin doesn't already have it.
local function settingEnabled(self, key, default)
    local settings = self.ai_helper and self.ai_helper.settings
    local value = settings and settings[key]
    if value == nil then return default == true end
    return value ~= false
end

local function presenceMapEnabled(self)
    return self:settingEnabled(SETTING, true)
end

-- Absent-only injection: official upstream strings win if these keys ever
-- ship in the plugin's .po files. English is the base for every language
-- because loc:t() returns the raw key (never nil) for a missing msgid, so
-- the code's `or "English"` fallbacks cannot fire.
local function injectTranslations(self)
    local loc = self.loc
    if not loc or type(loc.translations) ~= "table" then return end
    local exact = TRANSLATIONS[loc.current_language] or {}
    for key, en_value in pairs(TRANSLATIONS.en) do
        if loc.translations[key] == nil then
            loc.translations[key] = exact[key] or en_value
        end
    end
end

-- Per-overlay presence data, computed once per open. The stock showTimeline
-- has already assigned pages and sorted plugin.timeline before building the
-- overlay, so raw_items is in display order and needs no further work.
local function ensureData(overlay)
    if overlay._presence then return overlay._presence end
    local events, chapters = {}, {}
    for _, ev in ipairs(overlay.raw_items or {}) do
        if ev.source ~= "series_prior" then
            events[#events + 1] = ev
            chapters[#chapters + 1] = ev.chapter or ""
        end
    end
    local characters = overlay.plugin.characters or {}
    local matrix = Presence.buildPresenceMatrix(events, characters)
    overlay._presence = {
        events = events,
        chapters = chapters,
        matrix = matrix,
        order = Presence.coverageOrder(matrix, characters, MIN_CHAPTER_COVERAGE),
    }
    return overlay._presence
end

local function isActive(overlay)
    local plugin = overlay.plugin
    return overlay.mode == "timeline" and plugin ~= nil
        and type(plugin.presenceMapEnabled) == "function" and plugin:presenceMapEnabled()
end

-- The filter lives on the plugin so reopening the timeline keeps it. Names
-- with no row here (another book, or a character merged away since) are
-- dropped: there would be no way to tap them off again.
local function currentFilter(overlay, data)
    local plugin = overlay.plugin
    local has_row = {}
    for _, name in ipairs(data.order) do has_row[name] = true end
    local kept = {}
    for _, name in ipairs(plugin.timeline_filter or {}) do
        if has_row[name] then kept[#kept + 1] = name end
    end
    plugin.timeline_filter = kept
    return kept
end

local function wrapPrepareItems(Overlay)
    local orig = Overlay.prepareItems
    Overlay.prepareItems = function(self, ...)
        orig(self, ...)
        if not isActive(self) then return end
        local data = ensureData(self)
        local filter = currentFilter(self, data)
        if #filter == 0 then return end
        local keep = {}
        for _, row in ipairs(Presence.matchingChapters(data.matrix, filter)) do
            keep[data.events[row]] = true
        end
        local kept = {}
        for _, item in ipairs(self.items or {}) do
            if keep[item] then kept[#kept + 1] = item end
        end
        self.items = kept
    end
end

-- A tap on a name, or on "All" (name == nil). Rebuilds the way the stock
-- prior-books toggle does: page one, re-filter, re-layout, repaint.
local function toggle(overlay, name)
    local plugin = overlay.plugin
    if name == nil then
        plugin.timeline_filter = {}
    else
        local kept, removed = {}, false
        for _, n in ipairs(plugin.timeline_filter or {}) do
            if n == name then removed = true else kept[#kept + 1] = n end
        end
        if not removed then kept[#kept + 1] = name end
        plugin.timeline_filter = kept
    end
    overlay.current_page = 1
    overlay:prepareItems()
    overlay:buildUI()
    UIManager:setDirty(overlay, "ui")
end

local function wrapBuildUI(Overlay)
    local orig = Overlay.buildUI
    Overlay.buildUI = function(self, ...)
        -- A tree shape rejected once will not be recognised on a later
        -- rebuild either, so stop building a strip and running stock twice.
        if warned.layout or not isActive(self) then return orig(self, ...) end
        local data = ensureData(self)
        if #data.order == 0 or #data.chapters == 0 then return orig(self, ...) end

        -- The timeline can open from a gesture without the menu ever being
        -- built, so the "All" label is injected here too.
        injectTranslations(self.plugin)
        local filter = currentFilter(self, data)
        local widgets = self._presence_widgets
        local scroller = widgets and widgets.scroller
        local loc = self.plugin.loc
        -- Strip.build runs inside the overlay's init, so anything that threw
        -- in there would take KOReader's main loop down with it.
        local built, strip, height = pcall(Strip.build, self, {
            data = data,
            selected = filter,
            matches = Presence.matchingChapters(data.matrix, filter),
            sw = self.sw,
            scroll = scroller and scroller.getScrolledOffset and scroller:getScrolledOffset() or nil,
            all_label = (loc and loc:t("menu_timeline_all")) or "All",
            on_toggle = function(name)
                local ok, err = pcall(toggle, self, name)
                if not ok then warn("filter toggle failed: " .. tostring(err)) end
            end,
        })
        if not built then
            warnOnce("render", "strip build failed: " .. tostring(strip)
                .. " - showing the stock timeline without the map")
            Strip.releaseWidgets(self)
            return orig(self, ...)
        end
        if not strip then
            warnOnce("render", tostring(height) .. " - showing the stock timeline without the map")
            return orig(self, ...)
        end

        -- Stock budgets its rows from self.sh. Lend it a screen shorter by
        -- the strip, so the strip's height comes out of the rows, then put
        -- the real height back whatever happened.
        local full_h = self.sh
        self.sh = full_h - height
        local ok, err = pcall(orig, self, ...)
        self.sh = full_h
        if not ok then error(err, 0) end

        if not Strip.insert(self, strip, full_h) then
            warnOnce("layout", "overlay layout not recognised - showing the stock timeline without the map")
            Strip.releaseWidgets(self)
            return orig(self, ...)
        end
    end
end

local function wrapOnCloseWidget(Overlay)
    local orig = Overlay.onCloseWidget
    Overlay.onCloseWidget = function(self, ...)
        Strip.freeBitmaps(self)
        Strip.releaseWidgets(self)
        if orig then return orig(self, ...) end
    end
end

local function menuEntry(self)
    return {
        text = (self.loc and self.loc:t("menu_timeline_presence_map"))
            or "Use Presence Map in Timeline",
        checked_func = function() return self:presenceMapEnabled() end,
        callback = function()
            if self.ai_helper and self.ai_helper.settings then
                local ok, err = pcall(function()
                    self.ai_helper:saveSettings({ [SETTING] = not self:presenceMapEnabled() })
                    -- Rebuild if the timeline is open behind this menu.
                    if self.timeline_menu then self:showTimeline() end
                end)
                if not ok then warn("presence map toggle failed: " .. tostring(err)) end
            end
        end,
        separator = true,
    }
end

local function missingCapability(XRayPlugin)
    for _, name in ipairs({ "getSubMenuItems", "showTimeline" }) do
        if type(XRayPlugin[name]) ~= "function" then return "method " .. name end
    end
    local ok, Overlay = pcall(pluginRequire, "xray_entity_list")
    if not ok or type(Overlay) ~= "table" then
        return "module xray_entity_list (needs plugin 26.9.4-beta or newer)"
    end
    for _, name in ipairs({ "prepareItems", "buildUI" }) do
        if type(Overlay[name]) ~= "function" then return "method xray_entity_list." .. name end
    end
    if not pcall(require, "ui/renderimage") then return "module ui/renderimage" end
    return nil, Overlay
end

local function patch_fn(XRayPlugin)
    if XRayPlugin.__timeline_patch_applied then return end
    local missing, Overlay = missingCapability(XRayPlugin)
    if missing then
        warn("missing " .. missing .. " - leaving the stock timeline in place")
        return
    end
    XRayPlugin.__timeline_patch_applied = true

    if XRayPlugin.presenceMapEnabled == nil then
        XRayPlugin.presenceMapEnabled = presenceMapEnabled
    end
    if XRayPlugin.settingEnabled == nil then
        XRayPlugin.settingEnabled = settingEnabled
    end

    local orig_getSubMenuItems = XRayPlugin.getSubMenuItems
    XRayPlugin.getSubMenuItems = function(self, ...)
        injectTranslations(self)
        local items = orig_getSubMenuItems(self, ...)
        if type(items) == "table" then
            table.insert(items, menuEntry(self))
        end
        return items
    end

    -- The overlay module is shared by every plugin instance; wrap it once.
    if not Overlay.__timeline_patch_applied then
        Overlay.__timeline_patch_applied = true
        wrapPrepareItems(Overlay)
        wrapBuildUI(Overlay)
        wrapOnCloseWidget(Overlay)
    end
end

local ok, userpatch = pcall(require, "userpatch")
if not ok or type(userpatch) ~= "table" or not userpatch.registerPatchPluginFunc then
    return
end
userpatch.registerPatchPluginFunc("xray", patch_fn)
