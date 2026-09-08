-- Stand-ins for the KOReader modules the patch requires. Widgets are plain
-- tables: Class:new{...} returns its argument, so specs can read fields and
-- children by index. Methods a class normally provides are copied onto the
-- instance so calls like widget:getSize() work.
local M = {}

local function widgetClass(defaults)
    local cls = {}
    for k, v in pairs(defaults or {}) do cls[k] = v end
    cls.new = function(_, t)
        t = t or {}
        for k, v in pairs(defaults or {}) do
            if t[k] == nil then t[k] = v end
        end
        return t
    end
    return cls
end

local function sized(w, h)
    return widgetClass({ getSize = function() return { w = w, h = h } end })
end

-- Returns captured (what the stubs saw) and stubs (name -> module table).
function M.make()
    local captured = { warnings = {}, renders = {}, dirty = 0, render_fails = false }
    local stubs = {}

    stubs.logger = {
        warn = function(...) table.insert(captured.warnings, tostring((...))) end,
        info = function() end,
        dbg = function() end,
    }
    stubs.userpatch = {
        registerPatchPluginFunc = function(name, fn)
            captured.plugin_name, captured.fn = name, fn
        end,
    }
    stubs.device = { screen = {
        scaleBySize = function(_, n) return n or 0 end,
        getWidth = function() return 600 end,
        getHeight = function() return 800 end,
    } }
    stubs["ui/uimanager"] = {
        setDirty = function() captured.dirty = captured.dirty + 1 end,
        show = function() end,
        close = function() end,
    }
    stubs["ffi/blitbuffer"] = { COLOR_BLACK = 0, Color8 = function(n) return n end }
    stubs["ui/font"] = { getFace = function(_, name, size) return { name = name, size = size } end }
    stubs["ui/geometry"] = { new = function(_, t)
        local g = {}
        for k, v in pairs(t or {}) do g[k] = v end
        return g
    end }
    stubs["ui/gesturerange"] = widgetClass()
    stubs["ui/renderimage"] = { renderImageData = function(_, svg, len, _, w, h)
        table.insert(captured.renders, { w = w, h = h, len = len })
        if captured.render_fails then return nil end
        return { w = w, h = h, free = function(self) self.freed = true end }
    end }

    stubs["ui/widget/button"] = sized(40, 24)
    stubs["ui/widget/textwidget"] = sized(120, 20)
    stubs["ui/widget/linewidget"] = widgetClass()
    stubs["ui/widget/verticalspan"] = widgetClass()
    stubs["ui/widget/horizontalspan"] = widgetClass()
    stubs["ui/widget/verticalgroup"] = widgetClass({
        resetLayout = function(self) self.reset = true end,
    })
    stubs["ui/widget/horizontalgroup"] = widgetClass()
    stubs["ui/widget/imagewidget"] = widgetClass({
        getSize = function(self) return { w = self.image.w, h = self.image.h } end,
        paintTo = function() end,
    })
    stubs["ui/widget/container/inputcontainer"] = widgetClass()
    stubs["ui/widget/container/centercontainer"] = widgetClass()
    stubs["ui/widget/container/leftcontainer"] = widgetClass()
    stubs["ui/widget/container/scrollablecontainer"] = widgetClass({
        getScrollbarWidth = function() return 12 end,
        onCloseWidget = function(self) self.closed = true end,
        setScrolledOffset = function(self, offset) self.offset = offset end,
        getScrolledOffset = function(self) return self.offset or { x = 0, y = 0 } end,
    })
    -- pluginRequire finds the plugin's require prefix by this loaded module.
    stubs.xray_ui = {}

    return captured, stubs
end

-- Installs the stubs in package.loaded for the duration of fn, then restores.
function M.with(stubs, fn)
    local saved = {}
    for name, stub in pairs(stubs) do
        saved[name] = package.loaded[name]
        package.loaded[name] = stub
    end
    local ok, err = pcall(fn)
    for name in pairs(stubs) do package.loaded[name] = saved[name] end
    if not ok then error(err, 0) end
end

return M
