require("spec.spec_helper")

-- Loads the BUILT artifact under stubbed KOReader modules and captures the
-- function it registers with userpatch. Every test calls withArtifact so
-- stubs never leak between tests.
local STUB_NAMES = {
    "userpatch", "logger", "device",
    "ui/uimanager", "ffi/blitbuffer", "ui/font", "ui/geometry",
    "ui/gesturerange", "ui/size", "ui/widget/button",
    "ui/widget/container/framecontainer", "ui/widget/container/inputcontainer",
    "ui/widget/infomessage", "ui/widget/linewidget", "ui/widget/textboxwidget",
    "ui/widget/verticalgroup", "ui/widget/verticalspan",
    "xray_theme", "xray_utils", "xray_ui",
}

local function makeStubs()
    local captured = { warnings = {} }
    local stubs = {}
    for _, name in ipairs(STUB_NAMES) do stubs[name] = {} end
    stubs.userpatch = {
        registerPatchPluginFunc = function(plugin_name, fn)
            captured.plugin_name, captured.fn = plugin_name, fn
        end,
    }
    stubs.logger = {
        warn = function(...) table.insert(captured.warnings, tostring((...))) end,
        info = function() end, dbg = function() end,
    }
    stubs.device = { screen = {
        scaleBySize = function(_, n) return n or 0 end,
        getWidth = function() return 600 end,
        getHeight = function() return 800 end,
    } }
    -- The region subclasses InputContainer at chunk load time.
    stubs["ui/widget/container/inputcontainer"] = {
        extend = function(base, proto) return setmetatable(proto, { __index = base }) end,
    }
    return captured, stubs
end

local function withArtifact(fn)
    local captured, stubs = makeStubs()
    local saved = {}
    for name, stub in pairs(stubs) do
        saved[name] = package.loaded[name]
        package.loaded[name] = stub
    end
    local ok, err = pcall(function()
        dofile("patches/2-xray-timeline-presence-map.lua")
        fn(captured)
    end)
    for name in pairs(stubs) do package.loaded[name] = saved[name] end
    assert.is_true(ok, tostring(err))
end

-- A class with every capability patch_fn checks for.
local function fullClass()
    local class = {}
    for _, m in ipairs({ "showTimeline", "getSubMenuItems", "showTimelineEventDetails",
                         "assignTimelinePages", "sortTimelineByTOC", "log" }) do
        class[m] = function() end
    end
    class.getSubMenuItems = function(self) return { { text = "a" }, { text = "b" } } end
    return class
end

describe("patch smoke", function()

    it("registers a patch function for the xray plugin", function()
        withArtifact(function(captured)
            assert.are.equal("xray", captured.plugin_name)
            assert.are.equal("function", type(captured.fn))
        end)
    end)

    it("leaves the class stock when a required method is missing", function()
        withArtifact(function(captured)
            local class = fullClass()
            class.assignTimelinePages = nil
            local orig_show = class.showTimeline
            captured.fn(class)
            assert.are.equal(orig_show, class.showTimeline)
            assert.are.equal(nil, class.presenceMapEnabled)
            assert.are.equal(1, #captured.warnings)
        end)
    end)

end)
