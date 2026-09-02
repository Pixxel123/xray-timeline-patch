-- Adapter for xray-timeline-patch. NOT loadable standalone: the build
-- prepends the chunk-locals `Presence` (inlined xray_presencemap module)
-- and `TRANSLATIONS` (5 keys x 17 languages). tools/build.lua concatenates
-- src/xray_presencemap.lua + src/translations.lua + this file.

local Blitbuffer      = require("ffi/blitbuffer")
local Button          = require("ui/widget/button")
local Font            = require("ui/font")
local FrameContainer  = require("ui/widget/container/framecontainer")
local Geom            = require("ui/geometry")
local GestureRange    = require("ui/gesturerange")
local InfoMessage     = require("ui/widget/infomessage")
local InputContainer  = require("ui/widget/container/inputcontainer")
local LineWidget      = require("ui/widget/linewidget")
local Screen          = require("device").screen
local Size            = require("ui/size")
local TextBoxWidget   = require("ui/widget/textboxwidget")
local UIManager       = require("ui/uimanager")
local VerticalGroup   = require("ui/widget/verticalgroup")
local VerticalSpan    = require("ui/widget/verticalspan")
local logger          = require("logger")

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

-- The ported timeline methods land on M; patch_fn installs them on the class.
local M = {}

-- REGION START -- ported from xray_ui.lua @ c082f69 by plan Task 4; do not hand-edit outside a sync
-- REGION END

-- Ported from the branch; installed only if the plugin doesn't already have
-- it (upstream may merge the menu-checked-func-guards branch on its own).
local function settingEnabled(self, key, default)
    local settings = self.ai_helper and self.ai_helper.settings
    local value = settings and settings[key]
    if value == nil then return default == true end
    return value ~= false
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

local function menuEntry(self)
    return {
        text = (self.loc and self.loc:t("menu_timeline_presence_map"))
            or "Use Presence Map in Timeline",
        checked_func = function() return self:presenceMapEnabled() end,
        callback = function()
            if self.ai_helper and self.ai_helper.settings then
                self.ai_helper:saveSettings({
                    timeline_presence_map = not self:presenceMapEnabled() })
                -- Rebuild if the Timeline is open behind this menu.
                if self.timeline_menu then self:showTimeline() end
            end
        end,
        separator = true,
    }
end

local REQUIRED_METHODS = {
    "showTimeline", "getSubMenuItems", "showTimelineEventDetails",
    "assignTimelinePages", "sortTimelineByTOC", "log",
}
local REQUIRED_MODULES = { "xray_theme", "xray_utils" }

local function missingCapability(XRayPlugin)
    if type(M.showTimeline) ~= "function" then return "ported region" end
    for _, name in ipairs(REQUIRED_METHODS) do
        if type(XRayPlugin[name]) ~= "function" then return "method " .. name end
    end
    for _, mod in ipairs(REQUIRED_MODULES) do
        if not pcall(pluginRequire, mod) then return "module " .. mod end
    end
    return nil
end

local function patch_fn(XRayPlugin)
    if XRayPlugin.__timeline_patch_applied then return end
    local missing = missingCapability(XRayPlugin)
    if missing then
        logger.warn("xray-timeline-patch: missing " .. missing
            .. " - leaving the stock timeline in place")
        return
    end
    XRayPlugin.__timeline_patch_applied = true

    XRayPlugin.timelineRowSpecs = M.timelineRowSpecs
    XRayPlugin.timelinePriorSpecs = M.timelinePriorSpecs
    XRayPlugin.presenceMapEnabled = M.presenceMapEnabled
    if XRayPlugin.settingEnabled == nil then
        XRayPlugin.settingEnabled = settingEnabled
    end

    local orig_showTimeline = XRayPlugin.showTimeline
    XRayPlugin.showTimeline = function(self, ...)
        injectTranslations(self)
        local ok, err = pcall(M.showTimeline, self, ...)
        if ok then return end
        logger.warn("xray-timeline-patch: timeline view failed, falling back to stock: "
            .. tostring(err))
        if self.timeline_menu then
            pcall(function() UIManager:close(self.timeline_menu) end)
            self.timeline_menu = nil
        end
        return orig_showTimeline(self, ...)
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
end

local ok, userpatch = pcall(require, "userpatch")
if not ok or type(userpatch) ~= "table" or not userpatch.registerPatchPluginFunc then
    return
end
userpatch.registerPatchPluginFunc("xray", patch_fn)
