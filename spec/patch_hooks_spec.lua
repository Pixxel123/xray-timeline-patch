require("spec.spec_helper")
local stubs_mod = require("spec.koreader_stubs")

-- A stand-in for the beta's EntityListOverlay: init runs prepareItems then
-- buildUI, prepareItems applies the search box, buildUI records the screen
-- height it was given and builds the same tree shape as the beta.
local function fakeOverlayClass()
    local O = {}
    O.__index = O
    function O:new(t)
        local o = setmetatable(t or {}, O)
        o.sw, o.sh = 600, 800
        o.current_page = o.current_page or 1
        o:prepareItems()
        o:buildUI()
        return o
    end
    function O:prepareItems()
        local items = {}
        for _, it in ipairs(self.raw_items or {}) do
            if not self.search_query or (it.event or ""):find(self.search_query, 1, true) then
                items[#items + 1] = it
            end
        end
        self.items = items
    end
    function O:buildUI()
        if self.explode then error("boom") end
        self.seen_sh = self.sh
        self.build_count = (self.build_count or 0) + 1
        local vg = { align = "left", { name = "header" }, { name = "list", items = self.items } }
        if self.bad_shape then vg[3] = { name = "extra" } end
        self[1] = {
            dimen = { w = 600, h = self.sh },
            { height = self.sh, vg },
            { dimen = { w = 600, h = self.sh } },
        }
        self.dimen = { x = 0, y = 0, w = 600, h = self.sh }
    end
    return O
end

local function pluginClass()
    local class = {}
    class.showTimeline = function(self) self.show_count = (self.show_count or 0) + 1 end
    class.getSubMenuItems = function() return { { text = "a" }, { text = "b" } } end
    return class
end

-- Victor in chapters 1-3, Creature 2-3, Walton 3; one prior-book recap.
local function pluginInstance(class)
    return setmetatable({
        timeline = {
            { chapter = "Chapter 1", event = "Victor studies alone." },
            { chapter = "Chapter 2", event = "Victor meets the Creature." },
            { chapter = "Chapter 3", event = "Walton hears Victor and the Creature." },
            { chapter = "Earlier book", event = "A recap.", source = "series_prior" },
        },
        characters = { { name = "Victor" }, { name = "Creature" }, { name = "Walton" } },
        ai_helper = {
            settings = {},
            saveSettings = function(self, t) for k, v in pairs(t) do self.settings[k] = v end end,
        },
        loc = {
            current_language = "en",
            translations = {},
            t = function(loc, key) return loc.translations[key] or key end,
        },
    }, { __index = class })
end

-- Loads the BUILT artifact under stubs, applies it to a fresh plugin class
-- and overlay class, and hands everything to fn.
local function withPatch(fn, tweak)
    local captured, stubs = stubs_mod.make()
    stubs.xray_entity_list = fakeOverlayClass()
    if tweak then tweak(captured, stubs) end
    stubs_mod.with(stubs, function()
        dofile("patches/2-xray-timeline-presence-map.lua")
        local class = pluginClass()
        captured.fn(class)
        fn(captured, stubs, class, stubs.xray_entity_list)
    end)
end

local function openTimeline(Overlay, plugin, extra)
    local t = { plugin = plugin, mode = "timeline", raw_items = plugin.timeline }
    for k, v in pairs(extra or {}) do t[k] = v end
    return Overlay:new(t)
end

describe("patch hooks", function()

    it("registers a patch function for the xray plugin", function()
        withPatch(function(captured)
            assert.are.equal("xray", captured.plugin_name)
            assert.are.equal("function", type(captured.fn))
        end)
    end)

    it("leaves everything stock when the overlay module is missing", function()
        withPatch(function(captured, stubs, class)
            assert.are.equal(1, #captured.warnings)
            assert.is_not_nil(captured.warnings[1]:find("xray_entity_list", 1, true))
            assert.is_nil(class.presenceMapEnabled)
            assert.are.equal(2, #class.getSubMenuItems())
        end, function(_, stubs) stubs.xray_entity_list = nil end)
    end)

    it("leaves everything stock when the overlay lacks buildUI", function()
        withPatch(function(captured, stubs, class, Overlay)
            assert.are.equal(1, #captured.warnings)
            assert.is_nil(class.presenceMapEnabled)
            assert.are.equal(nil, Overlay.__timeline_patch_applied)
        end, function(_, stubs) stubs.xray_entity_list.buildUI = nil end)
    end)

    it("installs the setting, the menu entry and the overlay wrappers once", function()
        withPatch(function(captured, stubs, class, Overlay)
            assert.are.equal(0, #captured.warnings)
            assert.are.equal("function", type(class.presenceMapEnabled))
            assert.are.equal("function", type(class.settingEnabled))
            local plugin = pluginInstance(class)
            local items = plugin:getSubMenuItems()
            assert.are.equal(3, #items)
            assert.are.equal("function", type(items[3].checked_func))
            assert.are.equal("function", type(items[3].callback))
            assert.is_true(items[3].checked_func())
            local wrapped = Overlay.buildUI
            captured.fn(pluginClass())
            assert.are.equal(wrapped, Overlay.buildUI)
        end)
    end)

    it("does not overwrite an existing settingEnabled", function()
        local marker = function() return true end
        withPatch(function(_, _, class)
            assert.are.equal(marker, class.settingEnabled)
        end, function(captured, stubs)
            -- Apply the patch to a class that already has settingEnabled.
            stubs.userpatch.registerPatchPluginFunc = function(name, fn)
                captured.plugin_name = name
                captured.fn = function(class) class.settingEnabled = marker; fn(class) end
            end
        end)
    end)

    it("does not overwrite an existing presenceMapEnabled", function()
        local marker = function() return true end
        withPatch(function(_, _, class)
            assert.are.equal(marker, class.presenceMapEnabled)
        end, function(captured, stubs)
            -- Apply the patch to a class that already has presenceMapEnabled.
            stubs.userpatch.registerPatchPluginFunc = function(name, fn)
                captured.plugin_name = name
                captured.fn = function(class) class.presenceMapEnabled = marker; fn(class) end
            end
        end)
    end)

    describe("prepareItems", function()

        it("lists everything and starts an empty filter when nothing is selected", function()
            withPatch(function(_, _, class, Overlay)
                local plugin = pluginInstance(class)
                local o = openTimeline(Overlay, plugin)
                assert.are.equal(4, #o.items)
                assert.are.same({}, plugin.timeline_filter)
            end)
        end)

        it("keeps only the selected character's chapters, by identity, and drops prior books", function()
            withPatch(function(_, _, class, Overlay)
                local plugin = pluginInstance(class)
                plugin.timeline_filter = { "Creature" }
                local o = openTimeline(Overlay, plugin)
                assert.are.equal(2, #o.items)
                assert.are.equal(plugin.timeline[2], o.items[1])
                assert.are.equal(plugin.timeline[3], o.items[2])
            end)
        end)

        it("composes with the stock search as an AND", function()
            withPatch(function(_, _, class, Overlay)
                local plugin = pluginInstance(class)
                plugin.timeline_filter = { "Creature" }
                local o = openTimeline(Overlay, plugin, { search_query = "Walton" })
                assert.are.equal(1, #o.items)
                assert.are.equal(plugin.timeline[3], o.items[1])
            end)
        end)

        it("requires every selected character", function()
            withPatch(function(_, _, class, Overlay)
                local plugin = pluginInstance(class)
                plugin.timeline_filter = { "Victor", "Walton" }
                local o = openTimeline(Overlay, plugin)
                assert.are.equal(1, #o.items)
                assert.are.equal(plugin.timeline[3], o.items[1])
            end)
        end)

        it("drops filter names that have no row", function()
            withPatch(function(_, _, class, Overlay)
                local plugin = pluginInstance(class)
                plugin.timeline_filter = { "Nobody", "Victor" }
                local o = openTimeline(Overlay, plugin)
                assert.are.same({ "Victor" }, plugin.timeline_filter)
                assert.are.equal(3, #o.items)
            end)
        end)

        it("leaves other list modes alone", function()
            withPatch(function(_, _, class, Overlay)
                local plugin = pluginInstance(class)
                plugin.timeline_filter = { "Creature" }
                local o = Overlay:new{ plugin = plugin, mode = "characters", raw_items = plugin.characters }
                assert.are.equal(3, #o.items)
                assert.are.equal(800, o.seen_sh)
            end)
        end)

        it("does nothing while the setting is off", function()
            withPatch(function(_, _, class, Overlay)
                local plugin = pluginInstance(class)
                plugin.ai_helper.settings.timeline_presence_map = false
                plugin.timeline_filter = { "Creature" }
                local o = openTimeline(Overlay, plugin)
                assert.are.equal(4, #o.items)
                assert.are.equal(800, o.seen_sh)
                assert.is_nil(o._presence_widgets)
            end)
        end)

    end)

    describe("buildUI", function()

        it("lends the stock layout a shorter screen and slots the strip under the header", function()
            withPatch(function(captured, _, class, Overlay)
                local plugin = pluginInstance(class)
                local o = openTimeline(Overlay, plugin)
                -- 3 rows: 6 + 60 + 4 = 70, plus line 1 and span 4
                assert.are.equal(800 - 75, o.seen_sh)
                local vg = o[1][1][1]
                assert.are.equal(3, #vg)
                assert.are.equal("header", vg[1].name)
                assert.are.equal("list", vg[3].name)
                assert.are.equal(800, o[1][1].height)
                assert.are.equal(800, o[1].dimen.h)
                assert.are.equal(800, o[1][2].dimen.h)
                assert.are.equal(800, o.dimen.h)
                assert.are.equal(0, #captured.warnings)
                assert.is_table(o._presence_widgets.names)
            end)
        end)

        it("falls back to the plain stock list, once warned, on an unrecognised tree", function()
            withPatch(function(captured, _, class, Overlay)
                local plugin = pluginInstance(class)
                local o = openTimeline(Overlay, plugin, { bad_shape = true })
                assert.are.equal(2, o.build_count)
                assert.are.equal(800, o.seen_sh)
                assert.are.equal(3, #o[1][1][1])
                assert.are.equal(1, #captured.warnings)
                assert.is_nil(o._presence_widgets)
                local renders = #captured.renders
                o:buildUI()
                assert.are.equal(1, #captured.warnings)
                -- short-circuited: stock ran once more and nothing was drawn
                assert.are.equal(3, o.build_count)
                assert.are.equal(renders, #captured.renders)
            end)
        end)

        it("falls back to the stock list when the strip cannot render", function()
            withPatch(function(captured, _, class, Overlay)
                captured.render_fails = true
                local plugin = pluginInstance(class)
                local o = openTimeline(Overlay, plugin)
                assert.are.equal(1, o.build_count)
                assert.are.equal(800, o.seen_sh)
                assert.are.equal(2, #o[1][1][1])
                assert.are.equal(1, #captured.warnings)
            end)
        end)

        it("falls back to the stock list, once warned, when the strip build throws", function()
            withPatch(function(captured, _, class, Overlay)
                local plugin = pluginInstance(class)
                local o = openTimeline(Overlay, plugin)
                assert.are.equal(1, o.build_count)
                assert.are.equal(800, o.seen_sh)
                assert.are.equal(2, #o[1][1][1])
                assert.are.equal(1, #captured.warnings)
                assert.is_not_nil(captured.warnings[1]:find("widget boom", 1, true))
                assert.is_nil(o._presence_widgets)
                o:buildUI()
                assert.are.equal(1, #captured.warnings)
            end, function(_, stubs)
                -- The strip's body group; the stock fake never builds one.
                stubs["ui/widget/horizontalgroup"].new = function() error("widget boom") end
            end)
        end)

        it("re-raises a stock buildUI error with the height restored", function()
            withPatch(function(_, _, class, Overlay)
                local plugin = pluginInstance(class)
                local o = openTimeline(Overlay, plugin)
                -- The fake's stock buildUI throws when self.explode is set.
                o.explode = true
                local ok, err = pcall(o.buildUI, o)
                assert.is_false(ok)
                assert.is_not_nil(tostring(err):find("boom", 1, true))
                assert.are.equal(800, o.sh)
            end)
        end)

        it("injects the All label even when the menu was never opened", function()
            withPatch(function(_, _, class, Overlay)
                local plugin = pluginInstance(class)
                plugin.timeline_filter = { "Victor" }
                openTimeline(Overlay, plugin)
                assert.are.equal("All", plugin.loc.translations.menu_timeline_all)
            end)
        end)

    end)

    describe("tapping the strip", function()

        it("toggles the tapped name, resets to page one and rebuilds", function()
            withPatch(function(captured, _, class, Overlay)
                local plugin = pluginInstance(class)
                local o = openTimeline(Overlay, plugin, { current_page = 5 })
                local names = o._presence_widgets.names
                names:paintTo(nil, 0, 100)
                names:onTap(nil, { pos = { x = 5, y = 100 + 6 + 20 + 3 } })
                assert.are.same({ "Creature" }, plugin.timeline_filter)
                assert.are.equal(1, o.current_page)
                assert.are.equal(2, o.build_count)
                assert.are.equal(1, captured.dirty)
                assert.are.equal(2, #o.items)
                -- the caption band now takes the button's height plus 4
                assert.are.equal(800 - (75 + 28), o.seen_sh)
            end)
        end)

        it("tapping a selected name again removes it", function()
            withPatch(function(_, _, class, Overlay)
                local plugin = pluginInstance(class)
                plugin.timeline_filter = { "Creature" }
                local o = openTimeline(Overlay, plugin)
                local names = o._presence_widgets.names
                names:paintTo(nil, 0, 100)
                names:onTap(nil, { pos = { x = 5, y = 100 + 6 + 20 + 3 } })
                assert.are.same({}, plugin.timeline_filter)
                assert.are.equal(4, #o.items)
            end)
        end)

        it("ignores a tap below the last row", function()
            withPatch(function(_, _, class, Overlay)
                local plugin = pluginInstance(class)
                local o = openTimeline(Overlay, plugin)
                local names = o._presence_widgets.names
                names:paintTo(nil, 0, 100)
                names:onTap(nil, { pos = { x = 5, y = 100 + 6 + 60 + 1 } })
                assert.are.same({}, plugin.timeline_filter)
                assert.are.equal(1, o.build_count)
            end)
        end)

        it("All clears the filter", function()
            withPatch(function(_, _, class, Overlay)
                local plugin = pluginInstance(class)
                plugin.timeline_filter = { "Victor", "Creature" }
                local o = openTimeline(Overlay, plugin)
                o._presence_widgets.all.callback()
                assert.are.same({}, plugin.timeline_filter)
                assert.are.equal(4, #o.items)
                assert.is_nil(o._presence_widgets.all)
            end)
        end)

        it("logs and survives a toggle that throws", function()
            withPatch(function(captured, _, class, Overlay)
                local plugin = pluginInstance(class)
                local o = openTimeline(Overlay, plugin)
                local names = o._presence_widgets.names
                names:paintTo(nil, 0, 100)
                o.prepareItems = function() error("kaboom") end
                names:onTap(nil, { pos = { x = 5, y = 100 + 6 + 3 } })
                assert.are.equal(1, #captured.warnings)
                assert.is_not_nil(captured.warnings[1]:find("kaboom", 1, true))
            end)
        end)

    end)

    it("frees the cached bitmaps when the overlay closes", function()
        withPatch(function(_, _, class, Overlay)
            local plugin = pluginInstance(class)
            local o = openTimeline(Overlay, plugin)
            local bbs = o._presence_bitmaps
            assert.is_table(bbs)
            o:onCloseWidget()
            assert.is_true(bbs.names.freed)
            assert.is_true(bbs.grid.freed)
            assert.is_nil(o._presence_bitmaps)
            assert.is_nil(o._presence_widgets)
        end)
    end)

    it("closes the strip's scroller when the overlay closes", function()
        withPatch(function(_, _, class, Overlay)
            local plugin = pluginInstance(class)
            -- Five rows, so the strip scrolls and owns a ScrollableContainer.
            plugin.characters = {
                { name = "Victor" }, { name = "Creature" }, { name = "Walton" },
                { name = "Elizabeth" }, { name = "Clerval" },
            }
            plugin.timeline = {
                { chapter = "Chapter 1",
                  event = "Victor, the Creature, Walton, Elizabeth and Clerval meet." },
                { chapter = "Chapter 2",
                  event = "Victor, the Creature, Walton, Elizabeth and Clerval part." },
                { chapter = "Chapter 3", event = "Victor is alone." },
            }
            local o = openTimeline(Overlay, plugin)
            local scroller = o._presence_widgets.scroller
            assert.is_table(scroller)
            o:onCloseWidget()
            assert.is_true(scroller.closed)
            assert.is_nil(o._presence_widgets)
        end)
    end)

    it("injects translations absent-only from the menu", function()
        withPatch(function(_, _, class)
            local T = dofile("src/translations.lua")
            local plugin = pluginInstance(class)
            plugin.loc.current_language = "de"
            plugin.loc.translations.menu_timeline_all = "OFFICIAL"
            plugin:getSubMenuItems()
            assert.are.equal("OFFICIAL", plugin.loc.translations.menu_timeline_all)
            assert.are.equal(T.de.menu_timeline_presence_map,
                plugin.loc.translations.menu_timeline_presence_map)
        end)
    end)

    it("the menu entry flips the setting and reopens an open timeline", function()
        withPatch(function(_, _, class)
            local plugin = pluginInstance(class)
            local items = plugin:getSubMenuItems()
            plugin.timeline_menu = {}
            items[3].callback()
            assert.are.equal(false, plugin.ai_helper.settings.timeline_presence_map)
            assert.is_false(items[3].checked_func())
            assert.are.equal(1, plugin.show_count)
            plugin.timeline_menu = nil
            items[3].callback()
            assert.are.equal(true, plugin.ai_helper.settings.timeline_presence_map)
            assert.are.equal(1, plugin.show_count)
        end)
    end)

end)
