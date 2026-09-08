-- Presence strip for the stock timeline overlay (xray_entity_list.lua).
-- Builds the widget the adapter slots under the overlay's header, owns the
-- cache of rendered bitmaps, and knows the shape of the stock tree it goes
-- into. It knows nothing about the plugin: the caller passes data and an
-- on_toggle callback.
--
-- NOT loadable standalone: the build prepends the chunk-local `Presence`
-- (src/xray_presencemap.lua). The spec sets _G.Presence instead.

local Blitbuffer          = require("ffi/blitbuffer")
local Button              = require("ui/widget/button")
local CenterContainer     = require("ui/widget/container/centercontainer")
local Font                = require("ui/font")
local Geom                = require("ui/geometry")
local GestureRange        = require("ui/gesturerange")
local HorizontalGroup     = require("ui/widget/horizontalgroup")
local HorizontalSpan      = require("ui/widget/horizontalspan")
local ImageWidget         = require("ui/widget/imagewidget")
local InputContainer      = require("ui/widget/container/inputcontainer")
local LeftContainer       = require("ui/widget/container/leftcontainer")
local LineWidget          = require("ui/widget/linewidget")
local ScrollableContainer = require("ui/widget/container/scrollablecontainer")
local Screen              = require("device").screen
local TextWidget          = require("ui/widget/textwidget")
local VerticalGroup       = require("ui/widget/verticalgroup")
local VerticalSpan        = require("ui/widget/verticalspan")

local M = {}

M.VISIBLE_ROWS = 4
-- Only long-press is left to the rows underneath; a drag (pan) and a flick
-- (swipe) both scroll the strip. ScrollableContainer acts on a pan only when
-- the touch began inside it, so the list below still pans freely.
local IGNORED_GESTURES = { "hold", "hold_release", "hold_pan" }

local function sc(n) return Screen:scaleBySize(n) end

-- All in scale units. name_width and the row metrics are what the SVG
-- builders draw with; col_width is filled in once the column count is known.
local function geometry(sw, scrolls)
    local pad = sc(6)
    local sbw = scrolls and ScrollableContainer:getScrollbarWidth() or 0
    local name_width = math.floor(sw * 0.22)
    local viewport_w = sw - pad * 2 - name_width - sbw
    return {
        pad = pad,
        viewport_w = viewport_w,
        max_cols = math.max(1, math.floor(viewport_w / sc(16))),
        name_width = name_width,
        row_height = sc(20),
        top_padding = sc(6),
        marker = sc(9),
        label_size = sc(9),
    }
end

function M.freeBitmaps(overlay)
    local cache = overlay._presence_bitmaps
    overlay._presence_bitmaps = nil
    if not cache then return end
    for _, key in ipairs({ "names", "grid" }) do
        local bb = cache[key]
        if bb and bb.free then bb:free() end
    end
end

-- A ScrollableContainer allocates a screen-sized offscreen Blitbuffer on its
-- first paint and frees it in onCloseWidget (its GC finalizer is a backstop
-- the collector does not pace, C heap being invisible to it). Every rebuild
-- makes a new container, so close the one it replaces.
function M.releaseWidgets(overlay)
    local widgets = overlay._presence_widgets
    overlay._presence_widgets = nil
    if not widgets then return end
    local scroller = widgets.scroller
    if scroller and scroller.onCloseWidget then scroller:onCloseWidget() end
end

-- Rasterize each half at exactly its own size; a mismatch would send
-- renderimage down its scaling path and blur the pips.
local function render(order, selected, matrix, columns, match_cols, geom)
    local RenderImage = require("ui/renderimage")
    local names_svg, nw, nh = Presence.buildStripNamesSVG(order, selected, geom)
    local grid_svg, gw, gh = Presence.buildStripGridSVG(
        matrix, order, columns, selected, geom, match_cols)
    local ok_n, names_bb = pcall(RenderImage.renderImageData, RenderImage,
        names_svg, #names_svg, false, nw, nh)
    local ok_g, grid_bb = pcall(RenderImage.renderImageData, RenderImage,
        grid_svg, #grid_svg, false, gw, gh)
    if ok_n and names_bb and ok_g and grid_bb then
        return { names = names_bb, grid = grid_bb, height = nh }
    end
    if ok_n and names_bb and names_bb.free then names_bb:free() end
    if ok_g and grid_bb and grid_bb.free then grid_bb:free() end
    return nil
end

-- Bitmaps live on the overlay across its rebuilds (every page turn and
-- d-pad move rebuilds the whole tree) and are replaced when the key changes.
local function bitmapsFor(overlay, key, ...)
    local cache = overlay._presence_bitmaps
    if cache and cache.key == key then return cache end
    M.freeBitmaps(overlay)
    cache = render(...)
    if cache then
        cache.key = key
        overlay._presence_bitmaps = cache
    end
    return cache
end

-- The name gutter as a tap target. paintTo records where it was drawn, so
-- a tap's y can be turned into a row even inside a scrolled container.
local function namesWidget(bb, geom, order, on_toggle)
    local image = ImageWidget:new{ image = bb, image_disposable = false }
    local names = InputContainer:new{ image }
    local size = image:getSize()
    names.dimen = Geom:new{ x = 0, y = 0, w = size.w, h = size.h }
    names.ges_events = {
        Tap = { GestureRange:new{ ges = "tap", range = function() return names.dimen end } },
    }
    function names:getSize() return image:getSize() end
    function names:paintTo(target, x, y)
        local s = image:getSize()
        self.dimen = Geom:new{ x = x, y = y, w = s.w, h = s.h }
        image:paintTo(target, x, y)
    end
    function names:onTap(_, ges)
        local row = Presence.rowAt(ges.pos.y - self.dimen.y, geom, #order)
        if row then on_toggle(order[row]) end
        return true
    end
    return names
end

-- The band has to be at least as tall as the button: LeftContainer centres
-- its child on dimen.h without growing, so a taller button would spill past
-- the band and have its bottom border painted over by the body below.
local function captionHeight(all_button)
    return math.max(sc(24), all_button:getSize().h + sc(4))
end

local function captionRow(sw, text, all_button, cap_h)
    local label = TextWidget:new{
        text = text,
        face = Font:getFace("cfont", 13),
        bold = true,
        fgcolor = Blitbuffer.COLOR_BLACK,
        max_width = sw - sc(40) - all_button:getSize().w,
    }
    local gap = math.max(sc(8), sw - sc(32) - label:getSize().w - all_button:getSize().w)
    return LeftContainer:new{
        dimen = Geom:new{ w = sw, h = cap_h },
        HorizontalGroup:new{
            align = "center",
            HorizontalSpan:new{ width = sc(16) },
            label,
            HorizontalSpan:new{ width = gap },
            all_button,
        },
    }
end

-- ctx: data {matrix, order, chapters}, selected (names), matches (row
-- indices from Presence.matchingChapters), sw (px), all_label,
-- on_toggle(name or nil for "All"), scroll (saved offset or nil).
-- Returns widget, height  or  nil, reason.
function M.build(overlay, ctx)
    -- Safe here: the caller has already read the outgoing scroll offset into
    -- ctx.scroll, and every path out of this function replaces the widgets.
    M.releaseWidgets(overlay)
    local order, selected = ctx.data.order, ctx.selected
    local n_rows = #order
    local scrolls = n_rows > M.VISIBLE_ROWS
    local filtering = #selected > 0
    local sw = ctx.sw
    local geom = geometry(sw, scrolls)

    -- One column per chapter while they stay at least 16 units wide; past
    -- that each column covers a span so the whole book still fits.
    local matrix, columns, match_cols = ctx.data.matrix, ctx.data.chapters, ctx.matches
    if #columns > geom.max_cols then
        matrix, match_cols, columns = Presence.bucketMatrix(matrix, ctx.matches, geom.max_cols)
    end
    geom.col_width = math.floor(geom.viewport_w / math.max(1, #columns))

    local key = table.concat(selected, "\n") .. "|" .. tostring(sw)
    local bbs = bitmapsFor(overlay, key, order, selected, matrix, columns, match_cols, geom)
    if not bbs then
        return nil, "strip render failed"
    end

    local widgets = { names = namesWidget(bbs.names, geom, order, ctx.on_toggle) }
    local body = HorizontalGroup:new{
        align = "top",
        HorizontalSpan:new{ width = geom.pad },
        widgets.names,
        ImageWidget:new{ image = bbs.grid, image_disposable = false },
    }

    local parts = VerticalGroup:new{ align = "left" }
    local height = 0

    if filtering then
        widgets.all = Button:new{
            text = ctx.all_label,
            show_parent = overlay, -- onTapSelectButton refreshes show_parent
            text_font_size = 13,
            padding = sc(2),
            bordersize = sc(1),
            radius = sc(4),
            callback = function() ctx.on_toggle(nil) end,
        }
        local cap_h = captionHeight(widgets.all)
        table.insert(parts, captionRow(sw,
            Presence.captionText(selected, #ctx.matches), widgets.all, cap_h))
        height = height + cap_h
    end

    if scrolls then
        local view_h = Presence.stripHeight(M.VISIBLE_ROWS, geom)
        local scroller = ScrollableContainer:new{
            dimen = Geom:new{ w = sw, h = view_h },
            ignore_events = IGNORED_GESTURES,
            show_parent = overlay,
            body,
        }
        if ctx.scroll then
            -- A filter change cannot shrink the strip (rows never hide), but
            -- clamp anyway so a stale offset can never scroll past the end.
            local max_offset = math.max(0, bbs.height - view_h)
            scroller:setScrolledOffset(Geom:new{
                x = 0, y = math.max(0, math.min(ctx.scroll.y or 0, max_offset)) })
        end
        widgets.scroller = scroller
        table.insert(parts, scroller)
        height = height + view_h
    else
        table.insert(parts, body)
        height = height + bbs.height
    end

    table.insert(parts, CenterContainer:new{
        dimen = Geom:new{ w = sw, h = sc(1) },
        LineWidget:new{
            background = Blitbuffer.Color8(180),
            dimen = Geom:new{ w = sw - sc(32), h = sc(1) },
        },
    })
    table.insert(parts, VerticalSpan:new{ width = sc(4) })
    height = height + sc(1) + sc(4)

    overlay._presence_widgets = widgets
    return parts, height
end

-- Slot the strip into the tree the beta's buildUI builds:
--   overlay[1]        OverlapGroup { dimen }
--     [1]             main surface FrameContainer { height, [1] = VerticalGroup { header, list } }
--     [2]             BottomContainer { dimen } holding the footer
-- The stock code was run with a screen shorter by the strip's height, so
-- every height it recorded is put back to full_h here.
function M.insert(overlay, strip, full_h)
    local top = overlay[1]
    if type(top) ~= "table" or type(top.dimen) ~= "table" then return false end
    local surface, footer = top[1], top[2]
    if type(surface) ~= "table" or type(surface.height) ~= "number" then return false end
    if type(footer) ~= "table" or type(footer.dimen) ~= "table" then return false end
    local vg = surface[1]
    if type(vg) ~= "table" or #vg ~= 2 then return false end
    if type(overlay.dimen) ~= "table" then return false end

    table.insert(vg, 2, strip)
    if vg.resetLayout then vg:resetLayout() end
    surface.height = full_h
    top.dimen.h = full_h
    top._size = nil
    footer.dimen.h = full_h
    overlay.dimen.h = full_h
    return true
end

return M
