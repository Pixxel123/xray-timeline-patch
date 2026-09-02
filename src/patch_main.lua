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
-- How much of a large cast the header shows before it scrolls.
-- These areas ignore pan, so the mouse wheel (which arrives as a pan) scrolls
-- the chapter list instead. Swipe and the scrollbars still work here.
local HEADER_IGNORED_GESTURES = {
    "pan", "pan_release",          -- the mouse wheel arrives as a pan
    "key_pg_back", "key_pg_fwd",   -- page keys belong to the chapter list
}

local STRIP_VISIBLE_ROWS = 3   -- character rows in the presence chart
local BUTTON_VISIBLE_ROWS = 2  -- rows of filter buttons (3 buttons per row)
local PRIOR_VISIBLE_ROWS = 2   -- earlier books shown before the recap block scrolls
local MIN_CHAPTER_COVERAGE = 2 -- a character in fewer chapters is a walk-on

-- Restore a scroll position across a rebuild.
-- A filter change can leave less to scroll, so the saved offset is clamped to
-- what the new content can actually reach.
local function _restoreScroll(container, saved, content_h, viewport_h)
    if not saved then return end
    local max_offset = math.max(0, content_h - viewport_h)
    container:setScrolledOffset(Geom:new{
        x = 0,
        y = math.max(0, math.min(saved.y or 0, max_offset)),
    })
end

-- The timeline header: title bar, filter buttons, presence map. Embedded by
-- XRayTimelineView; the chapter list below it is XRayTimelineRowList.
local function _buildTimelineHeader(self, ctx)
    local presence = Presence
    local xray_theme = pluginRequire("xray_theme")
    local HorizontalGroup = require("ui/widget/horizontalgroup")
    local HorizontalSpan  = require("ui/widget/horizontalspan")
    local ScrollableContainer = require("ui/widget/container/scrollablecontainer")
    local TitleBar = require("ui/widget/titlebar")
    local sw = Screen:getWidth()
    local pad = Screen:scaleBySize(6)
    local sbw = ScrollableContainer:getScrollbarWidth()
    local components = { align = "left" }

    -- The real TitleBar: same centering, close icon and RTL handling as every
    -- other X-Ray screen, rather than hand-building the same thing.
    table.insert(components, TitleBar:new{
        width = sw,
        title = ctx.title,
        with_bottom_line = false,
        close_callback = function() if ctx.on_back then ctx.on_back() end end,
        show_parent = ctx.show_parent,
    })

    local all_label = ctx.all_label
    local defs = { { label = all_label, name = nil } }
    for _, name in ipairs(ctx.order) do
        defs[#defs + 1] = { label = name, name = name }
    end
    local is_selected = {}
    for _, name in ipairs(ctx.selected) do is_selected[name] = true end

    -- Three per row fits most full names; four truncates to "Victor Frank". Past
    -- BUTTON_VISIBLE_ROWS the group scrolls, so a large cast cannot crowd out
    -- the chapters.
    local per_row = 3
    local btn_scrolls = math.ceil(#defs / per_row) > BUTTON_VISIBLE_ROWS
    -- Wider inset than the rest of the header: labels are flush left inside
    -- borderless buttons, so the first column would sit against the screen edge.
    local btn_pad = Screen:scaleBySize(18)
    local btn_w = math.floor((sw - btn_pad * 2 - (btn_scrolls and sbw or 0)) / per_row)
    -- Rows stay left-aligned so buttons line up in a column. The block itself is
    -- centered below.
    local button_group = VerticalGroup:new{ align = "left" }
    local row_items = nil
    for i, def in ipairs(defs) do
        if (i - 1) % per_row == 0 then
            row_items = { align = "center" }
            table.insert(button_group, HorizontalGroup:new(row_items))
        end
        local is_on = (def.name == nil) and #ctx.selected == 0 or is_selected[def.name] or false
        -- A borderless Button with a filled/empty square, not CheckButton: the square
        -- reads better at this density and Button truncates with a real ellipsis.
        table.insert(row_items, Button:new{
            text = (is_on and "\u{25A0} " or "\u{25A1} ") .. def.label,
            width = btn_w,
            max_width = btn_w,
            align = "left",
            bordersize = 0,
            background = xray_theme.color_bg,
            text_font_size = 14,
            show_parent = ctx.show_parent,
            callback = function() ctx.on_toggle(def.name) end,
        })
    end
    local CenterContainer = require("ui/widget/container/centercontainer")
    if btn_scrolls then
        -- Full screen width, so this scrollbar lines up with the ones below it.
        -- The buttons are centered inside the container instead.
        local group_w = button_group:getSize().w
        local inset = math.max(0, math.floor((sw - sbw - group_w) / 2))
        local button_block = ScrollableContainer:new{
            dimen = Geom:new{
                w = sw,
                h = math.floor(button_group:getSize().h * BUTTON_VISIBLE_ROWS / #button_group),
            },
            ignore_events = HEADER_IGNORED_GESTURES,
            show_parent = ctx.show_parent,
            HorizontalGroup:new{
                align = "top",
                HorizontalSpan:new{ width = inset },
                button_group,
            },
        }
        -- Tapping a character rebuilds the whole view, so without this the list
        -- would jump back to the top and lose the button just tapped.
        _restoreScroll(button_block, ctx.scroll_state.buttons,
                       button_group:getSize().h, button_block.dimen.h)
        ctx.scrollers.buttons = button_block
        table.insert(components, button_block)
    else
        table.insert(components, CenterContainer:new{
            dimen = Geom:new{ w = sw, h = button_group:getSize().h },
            button_group,
        })
    end
    table.insert(components, VerticalSpan:new{ width = pad })

    local ncols = #ctx.chapters
    if ncols > 0 and ctx.show_map and #presence.shownNames(ctx.order, ctx.selected) > 0 then
        local RenderImage = require("ui/renderimage")
        local ImageWidget = require("ui/widget/imagewidget")

        local shown_rows = #presence.shownNames(ctx.order, ctx.selected)
        local strip_scrolls = shown_rows > STRIP_VISIBLE_ROWS
        local name_w = math.floor(sw * 0.22)
        local viewport_w = sw - pad * 2 - name_w - (strip_scrolls and sbw or 0)

        -- One column per chapter while they stay at least min_col wide.
        -- Past that, each column covers a span so the whole book still fits.
        local min_col = Screen:scaleBySize(16)
        local max_cols = math.max(1, math.floor(viewport_w / min_col))
        local bucketed_matrix, match_cols, ranges
        local columns = ctx.chapters
        if ncols > max_cols then
            bucketed_matrix, match_cols, ranges =
                presence.bucketMatrix(ctx.matrix, ctx.matches, max_cols)
            columns = ranges
        else
            match_cols = ctx.matches
        end
        ncols = #columns

        local geom = {
            name_width = name_w,
            col_width = math.floor(viewport_w / ncols),
            row_height = Screen:scaleBySize(20),
            top_padding = Screen:scaleBySize(6),
            marker = Screen:scaleBySize(9),
            label_size = Screen:scaleBySize(9),
        }

        local names_svg, nw, nh = presence.buildStripNamesSVG(ctx.order, ctx.selected, geom)
        local grid_svg, gw, gh = presence.buildStripGridSVG(
            bucketed_matrix or ctx.matrix, ctx.order, columns, ctx.selected, geom, match_cols)

        -- Rasterize each at exactly its own dimensions; a mismatch would send
        -- renderimage.lua down its scaleBlitBuffer path and blur the result.
        local ok_n, names_bb = pcall(RenderImage.renderImageData, RenderImage,
            names_svg, #names_svg, false, nw, nh)
        local ok_g, grid_bb = pcall(RenderImage.renderImageData, RenderImage,
            grid_svg, #grid_svg, false, gw, gh)

        if ok_n and names_bb and ok_g and grid_bb then
            -- Columns always fit the viewport, so the grid never scrolls
            -- sideways. Height is the constraint instead.
            local strip = HorizontalGroup:new{
                align = "top",
                HorizontalSpan:new{ width = pad },
                ImageWidget:new{ image = names_bb, image_disposable = true },
                ImageWidget:new{ image = grid_bb, image_disposable = true },
            }
            if strip_scrolls then
                -- Names and grid scroll together, so a row's marks never drift
                -- away from its name.
                local strip_block = ScrollableContainer:new{
                    dimen = Geom:new{
                        w = sw,
                        h = presence.stripHeight(STRIP_VISIBLE_ROWS, geom),
                    },
                    ignore_events = HEADER_IGNORED_GESTURES,
                    show_parent = ctx.show_parent,
                    strip,
                }
                _restoreScroll(strip_block, ctx.scroll_state.strip,
                               gh, strip_block.dimen.h)
                ctx.scrollers.strip = strip_block
                table.insert(components, strip_block)
            else
                table.insert(components, strip)
            end
            table.insert(components, VerticalSpan:new{ width = pad })
        else
            self:log("XRayPlugin: Timeline: strip render failed")
        end
    end

    -- Sort direction and the two jumps, in a fixed band of their own rather than
    -- folded into the filter block: that block scrolls away once the cast passes
    -- BUTTON_VISIBLE_ROWS, which is exactly when the sort state matters most.
    -- Hidden when the list is empty, so controls are never offered for nothing.
    if not ctx.empty_text and ctx.on_sort_toggle then
        -- Capped at a quarter of the usable width so the label between them can
        -- never be squeezed to nothing, or past it, on a narrow screen.
        local jump_w = math.min(Screen:scaleBySize(46), math.floor((sw - pad * 2) / 4))
        local sort_w = sw - pad * 2 - jump_w * 2
        local icon_px = Screen:scaleBySize(18)
        -- KOReader's own first/last-page chevrons rather than a glyph: the
        -- corner arrows that would say this in text sit outside the UI font and
        -- would render as tofu, while an icon has no font dependency at all.
        local function jump(icon, callback)
            return Button:new{
                icon = icon,
                icon_width = icon_px,
                icon_height = icon_px,
                width = jump_w,
                bordersize = 0,
                background = xray_theme.color_bg,
                show_parent = ctx.show_parent,
                callback = callback,
            }
        end
        -- The label names the current state, not what a tap would do, so the
        -- arrow and the words always agree. U+2191/2193 come from the same
        -- block as the arrows this plugin already draws elsewhere.
        table.insert(components, HorizontalGroup:new{
            align = "center",
            HorizontalSpan:new{ width = pad },
            jump("chevron.first",
                 function() if ctx.on_jump then ctx.on_jump("top") end end),
            Button:new{
                text = (ctx.sort_desc and "\u{2193} " or "\u{2191} ") .. (ctx.sort_label or ""),
                width = sort_w,
                max_width = sort_w,
                align = "center",
                bordersize = 0,
                background = xray_theme.color_bg,
                text_font_size = 14,
                show_parent = ctx.show_parent,
                callback = ctx.on_sort_toggle,
            },
            jump("chevron.last",
                 function() if ctx.on_jump then ctx.on_jump("bottom") end end),
        })
        table.insert(components, VerticalSpan:new{ width = pad })
    end

    -- Earlier books in the series, in a scroller of their own so a long series
    -- cannot push this book's chapters off the screen.
    -- The caller builds the list only when the block is open, so a list here
    -- means it is open.
    if ctx.prior_specs then
        table.insert(components, HorizontalGroup:new{
            align = "center",
            HorizontalSpan:new{ width = pad },
            Button:new{
                text = (ctx.prior_list and "▼ " or "► ") .. ctx.prior_label,
                width = sw - pad * 2,
                max_width = sw - pad * 2,
                align = "left",
                bordersize = 0,
                background = xray_theme.color_bg,
                text_font_size = 14,
                show_parent = ctx.show_parent,
                callback = ctx.on_prior_toggle,
            },
        })
        if ctx.prior_list then
            local content_h = ctx.prior_list:getSize().h
            local prior_block = ScrollableContainer:new{
                dimen = Geom:new{ w = sw, h = ctx.prior_view_height },
                ignore_events = HEADER_IGNORED_GESTURES,
                show_parent = ctx.show_parent,
                ctx.prior_list,
            }
            _restoreScroll(prior_block, ctx.scroll_state.prior,
                           content_h, ctx.prior_view_height)
            ctx.scrollers.prior = prior_block
            table.insert(components, prior_block)
        end
        table.insert(components, VerticalSpan:new{ width = pad })
    end

    if ctx.empty_text then
        table.insert(components, VerticalSpan:new{ width = pad * 4 })
        table.insert(components, TextBoxWidget:new{
            text = ctx.empty_text,
            face = Font:getFace("cfont", 17),
            width = sw - pad * 4,
            alignment = "center",
        })
    else
        table.insert(components, LineWidget:new{
            dimen = Geom:new{ w = sw, h = (Size.line and Size.line.thick) or 2 },
            background = xray_theme.color_border,
        })
    end

    return FrameContainer:new{
        bordersize = 0,
        padding = 0,
        background = xray_theme.color_bg,
        VerticalGroup:new(components),
    }
end

-- TextBoxWidget renders inline bold when the text opens with PTF_HEADER and the
-- bold runs are wrapped in PTF_BOLD_START/END. xray_settings_card does the same.
-- Using the frontend's own constants means an upstream change cannot silently
-- drop the bold.
local MARKUP_ON = TextBoxWidget.PTF_HEADER
local BOLD_ON = TextBoxWidget.PTF_BOLD_START
local BOLD_OFF = TextBoxWidget.PTF_BOLD_END

-- Full-screen timeline: header on top, then the chapters as headed paragraphs
-- (a Menu strips newlines, so it cannot put a summary beneath a heading).
local XRayTimelineView = InputContainer:extend{
    ui_instance = nil,
    header_ctx = nil,   -- built in init, once there is a show_parent to give it
    rows = nil,
}

function XRayTimelineView:init()
    local sw, sh = Screen:getWidth(), Screen:getHeight()
    self.dimen = Geom:new{ x = 0, y = 0, w = sw, h = sh }

    local Device = require("device")
    if Device.hasKeys and Device:hasKeys() then
        self.key_events = { Close = { { Device.input.group.Back } } }
    end
    -- No swipe-to-dismiss: a swipe the chapter list cannot consume would fall
    -- through and close the view mid-scroll. Use the close icon or Back key.

    -- Built here, not by the caller, so buttons and scrollers get a real
    -- show_parent; without one a scroller repaints via setDirty(nil).
    local xray_theme = pluginRequire("xray_theme")
    self.header_ctx.show_parent = self
    self.header = _buildTimelineHeader(self.ui_instance, self.header_ctx)

    local ScrollableContainer = require("ui/widget/container/scrollablecontainer")
    local header_h = self.header:getSize().h
    local body_h = sh - header_h
    if body_h < Screen:scaleBySize(60) then body_h = Screen:scaleBySize(60) end

    local body = ScrollableContainer:new{
        dimen = Geom:new{ w = sw, h = body_h },
        show_parent = self,
        self.rows,
    }
    self.body = body
    -- UIManager crops repaints to one registered scrollable per screen, and only
    -- the body is registered. Known consequence: a pan starting in the chapter
    -- list that crosses into the header band can be claimed by the wrong container.
    self.cropping_widget = body

    self[1] = FrameContainer:new{
        bordersize = 0,
        padding = 0,
        background = xray_theme.color_bg,
        VerticalGroup:new{
            align = "left",
            self.header,
            body,
        },
    }
end

-- Scroll the chapter list to one end. The list holds only the chapters matching
-- the current filter, so its ends already are the first and last match and no
-- index mapping is needed. Reversing the sort reverses the list, so "top" keeps
-- meaning the first row drawn rather than the earliest chapter.
--
-- scrollToRatio, not setScrolledOffset: the latter only assigns the offset and
-- leaves the scrollbar thumb where it was. scrollToRatio finishes with
-- _scrollBy(0, 0), which clamps against the container's own crop height --
-- narrower than dimen.h, since the scrollbar takes width -- then updates the
-- thumb and repaints. It centres on the ratio, so 0 and 1 clamp to exactly the
-- top and bottom.
function XRayTimelineView:jumpRowsTo(where)
    if not self.body or not self.body.scrollToRatio then return end
    self.body:scrollToRatio(nil, (where == "bottom") and 1 or 0)
end

function XRayTimelineView:onClose()
    UIManager:close(self)
    return true
end

function XRayTimelineView:onShow()
    UIManager:setDirty(self, "ui")
    return true
end

function XRayTimelineView:onCloseWidget()
    local ui = self.ui_instance
    if ui then
        ui.timeline_menu = nil
        if not ui._timeline_rebuilding then
            -- Filter state is per visit: reopening starts on All.
            ui.timeline_filter = {}
        end
        -- Only a real close returns to the X-Ray menu. Every filter tap also
        -- closes this view so showTimeline can rebuild it, and treating that as
        -- a close would stack a fresh menu underneath each time.
        if not ui.is_cancelled and not ui._timeline_rebuilding
                and ui.showFullXRayMenu then
            ui:showFullXRayMenu()
        end
    end
    UIManager:setDirty(nil, "ui")
end

-- The chapter list, built one row at a time as rows come into view.
--
-- TextBoxWidget lays out in the constructor, so building every row up front
-- cost 19MB and 84ms for 365 rows. Rows are a fixed height, so the list can
-- report its size without laying anything out, and paintTo builds only the
-- rows on screen.
-- One chapter: bold heading, then the summary beneath, capped to a fixed height.
local function _buildTimelineRowText(text_width, text_height, face, chapter, event)
    local function esc(t)
        -- The markup control chars must not appear in the content itself.
        return (tostring(t or ""):gsub("[\xEF][\xBF][\xB1-\xB3]", ""))
    end
    local body = esc(event)
    local text = MARKUP_ON .. BOLD_ON .. esc(chapter) .. BOLD_OFF
    if #body > 0 then text = text .. "\n" .. body end
    return TextBoxWidget:new{
        text = text,
        face = face,
        width = text_width,
        height = text_height,
        height_overflow_show_ellipsis = true,
        alignment = "left",
    }
end

-- Line height for a face, measured once. Building a TextBoxWidget is the only
-- way to ask, and too slow to repeat on every rebuild.
local _line_height_cache = {}
local function _timelineLineHeight(face)
    local cached = _line_height_cache[face]
    if not cached then
        local probe = TextBoxWidget:new{ text = "X", face = face, width = 200 }
        cached = probe:getLineHeight()
        probe:free()
        _line_height_cache[face] = cached
    end
    return cached
end

-- Rows kept either side of the viewport before eviction.
local KEEP_MARGIN = 20

local XRayTimelineRowList = InputContainer:extend{
    specs = nil,        -- { { chapter, event, ev }, ... }
    width = nil,
    text_width = nil,
    row_height = nil,
    text_height = nil,
    left_pad = 0,
    face = nil,
    on_hold_row = nil,
}

function XRayTimelineRowList:init()
    self._cache = {}
    self.dimen = Geom:new{ x = 0, y = 0, w = self.width, h = self:_totalHeight() }
    -- Tap opens the chapter's details; hold does the same.
    self.ges_events = {
        Tap = {
            GestureRange:new{ ges = "tap", range = function() return self.dimen end },
        },
        Hold = {
            GestureRange:new{ ges = "hold", range = function() return self.dimen end },
        },
    }
end

function XRayTimelineRowList:_totalHeight()
    return #self.specs * self.row_height
end

function XRayTimelineRowList:getSize()
    return Geom:new{ w = self.width, h = self:_totalHeight() }
end

function XRayTimelineRowList:_row(i)
    local widget = self._cache[i]
    if not widget then
        local spec = self.specs[i]
        widget = _buildTimelineRowText(self.text_width, self.text_height,
                                       self.face, spec.chapter, spec.event)
        self._cache[i] = widget
    end
    return widget
end

function XRayTimelineRowList:paintTo(bb, x, y)
    self.dimen.x, self.dimen.y = x, y
    local n = #self.specs
    if n == 0 then return end

    -- Rows intersecting the buffer. y is already shifted by the scroll offset.
    local first = math.max(1, math.floor(-y / self.row_height) + 1)
    local last = math.min(n, math.ceil((bb:getHeight() - y) / self.row_height))

    local gap = math.floor((self.row_height - self.text_height) / 2)
    for i = first, last do
        local top = y + (i - 1) * self.row_height
        self:_row(i):paintTo(bb, x + self.left_pad, top + gap)
        if i < n then
            bb:paintRect(x, top + self.row_height - 1, self.width, 1,
                         Blitbuffer.COLOR_LIGHT_GRAY)
        end
    end

    -- Drop rows well outside the viewport, or scrolling end to end would cache
    -- every row and defeat the point of the lazy list.
    local keep_from, keep_to = first - KEEP_MARGIN, last + KEEP_MARGIN
    for i, widget in pairs(self._cache) do
        if i < keep_from or i > keep_to then
            if widget.free then widget:free() end
            self._cache[i] = nil
        end
    end
end

function XRayTimelineRowList:_openRowAt(ges)
    if not (ges and ges.pos and self.on_hold_row) then return false end
    local offset = ges.pos.y - self.dimen.y
    local i = math.floor(offset / self.row_height) + 1
    if i >= 1 and i <= #self.specs then
        self.on_hold_row(self.specs[i])
        return true
    end
    return false
end

function XRayTimelineRowList:onTap(_, ges)
    return self:_openRowAt(ges)
end

function XRayTimelineRowList:onHold(_, ges)
    return self:_openRowAt(ges)
end

function XRayTimelineRowList:onCloseWidget()
    for _, w in pairs(self._cache or {}) do
        if w.free then w:free() end
    end
    self._cache = {}
end


-- None of this depends on which characters are filtered, and some of it is very
-- expensive. assignTimelinePages runs full-document findText scans for chapter
-- titles that miss the TOC, which would cost seconds on every filter tap.
-- Identity alone is not enough: merges and "fetch more characters" mutate
-- self.characters in place, so every field the map reads is compared as well.
-- That is the name and aliases, which decide presence, and the role, which
-- decides whether coverageOrder keeps a lead below the minimum. Aliases only
-- ever grow and a role change today arrives with a fresh self.timeline, so this
-- guards an invariant rather than a live staleness bug -- but the invariant is
-- then local to this function instead of resting on what the callers happen to
-- do.
--
-- Length-prefixed, so no name or alias can spell out a separator and pass
-- itself off as a different field boundary.
local function _field(parts, value)
    local text = tostring(value)
    parts[#parts + 1] = #text .. ":" .. text
end

local function _charactersSignature(characters)
    local parts = {}
    for _, c in ipairs(characters or {}) do
        _field(parts, c.name)
        _field(parts, c.role)
        local aliases = c.aliases or {}
        _field(parts, #aliases)
        for _, alias in ipairs(aliases) do _field(parts, alias) end
    end
    return table.concat(parts, "\30")
end

local function _timelineData(self)
    local signature = _charactersSignature(self.characters)
    local cache = self._timeline_cache
    if cache and cache.timeline == self.timeline
            and cache.characters == self.characters
            and cache.signature == signature then
        return cache
    end

    local utils = pluginRequire("xray_utils")
    local presence = Presence
    local toc = utils:flattenTOC(self.ui.document:getToc())
    -- Both mutate self.timeline in place, so its identity stays stable.
    self:assignTimelinePages(self.timeline, toc, true)
    self:sortTimelineByTOC(self.timeline)

    -- Matrix rows line up with current-book events only, in the same order, so
    -- index i means the same in both. Prior-book entries belong to no chapter
    -- here, so they are set aside for the recap block rather than dropped.
    local events, chapter_titles, prior_events = {}, {}, {}
    for _, ev in ipairs(self.timeline) do
        if ev.source == "series_prior" then
            prior_events[#prior_events + 1] = ev
        else
            events[#events + 1] = ev
            chapter_titles[#chapter_titles + 1] = ev.chapter or ""
        end
    end

    local characters = self.characters or {}
    local matrix = presence.buildPresenceMatrix(events, characters)
    cache = {
        timeline = self.timeline,
        characters = self.characters,
        signature = signature,
        events = events,
        chapter_titles = chapter_titles,
        prior_events = prior_events,
        matrix = matrix,
        order = presence.coverageOrder(matrix, characters, MIN_CHAPTER_COVERAGE),
    }
    self._timeline_cache = cache
    return cache
end

-- The current book's chapter rows in display order.
--
-- Returns a copy when reversing: the caller's list comes from the timeline
-- cache and is reused across filter taps, so reversing it in place would flip
-- it again on the next rebuild and the order would alternate as you tapped.
--
-- Prior-book rows are not passed through here. They belong to earlier books and
-- stay above the current book whichever way this one is sorted.
function M:timelineRowSpecs(specs, descending)
    if not descending then return specs end
    local out = {}
    for i = #specs, 1, -1 do out[#out + 1] = specs[i] end
    return out
end

-- One row per earlier book in the series, or nil when the block is hidden.
--
-- A character filter hides them: prior events are not in the presence matrix,
-- so they can never match. Listing them anyway would suggest they did.
function M:timelinePriorSpecs(prior_events, selected)
    if not prior_events or #prior_events == 0 then return nil end
    if selected and #selected > 0 then return nil end
    local specs = {}
    for _, ev in ipairs(prior_events) do
        -- A recap is a whole book's events joined with blank lines, which would
        -- waste one of the row's two preview lines. Only this copy is flattened;
        -- the details popup reads ev itself.
        local preview = (ev.event or ""):gsub("%s+", " "):match("^ *(.-) *$")
        specs[#specs + 1] = { chapter = ev.chapter or "", event = preview, ev = ev }
    end
    return specs
end

-- Whether the timeline shows its presence map. Unset means on.
function M:presenceMapEnabled()
    return self:settingEnabled("timeline_presence_map", true)
end

function M:showTimeline()
    if not self.timeline or #self.timeline == 0 then UIManager:show(InfoMessage:new{ text = self.loc:t("no_timeline_data"), timeout = 3 }); return end
    local presence = Presence
    local data = _timelineData(self)

    -- Character filter state lives on the plugin so a rebuild preserves it.
    local show_map = self:presenceMapEnabled()
    self.timeline_filter = self.timeline_filter or {}
    local filtering = #self.timeline_filter > 0

    -- Sort direction sits beside the filter and deliberately outside the
    -- _timelineData cache. Reversing is a display concern: the matrix and the
    -- coverage order the cache holds are the same either way, so keying on it
    -- would rebuild assignTimelinePages on every tap for no change.
    if self.timeline_sort_desc == nil then self.timeline_sort_desc = false end

    -- Closed on first open, so the chapter list stays visible.
    if self.series_prior_timeline_collapsed == nil then
        self.series_prior_timeline_collapsed = true
    end
    local prior_specs = self:timelinePriorSpecs(data.prior_events, self.timeline_filter)

    -- The header is rebuilt on every filter tap, so scroll positions are carried
    -- across. A position is kept even when its scroller disappears: filtering to
    -- one character collapses the map, and it should reopen where it was.
    local scroll_state = self._timeline_scroll_state or {}
    for key, sc in pairs(self._timeline_scrollers or {}) do
        if sc.getScrolledOffset then scroll_state[key] = sc:getScrolledOffset() end
    end
    self._timeline_scroll_state = scroll_state
    self._timeline_scrollers = {}

    local matches = presence.matchingChapters(data.matrix, self.timeline_filter)
    local is_match = {}
    for _, idx in ipairs(matches) do is_match[idx] = true end

    local row_specs = {}
    for i, ev in ipairs(data.events) do
        if is_match[i] then
            row_specs[#row_specs + 1] = { chapter = ev.chapter or "", event = ev.event or "", ev = ev }
        end
    end
    row_specs = self:timelineRowSpecs(row_specs, self.timeline_sort_desc)

    -- When a filter matches nothing the list stays empty and the message is
    -- drawn in the header, where it can be centered and has no row border.
    local all_label = self.loc:t("menu_timeline_all") or "All"
    local empty_text = nil
    if #row_specs == 0 then
        if filtering then
            empty_text = self.loc:t("timeline_no_shared_chapters",
                table.concat(self.timeline_filter, " \u{00B7} "), all_label)
        elseif not prior_specs then
            -- Not an empty timeline (caught above) but nothing for this book.
            -- If prior recaps exist they are the content, so say nothing.
            empty_text = self.loc:t("no_timeline_data")
        end
    end

    local header_ctx = {
        title = self.loc:t("menu_timeline"),
        order = data.order,
        matrix = data.matrix,
        chapters = data.chapter_titles,
        matches = matches,
        scroll_state = scroll_state,
        scrollers = self._timeline_scrollers,
        selected = self.timeline_filter,
        empty_text = empty_text,
        all_label = all_label,
        show_map = show_map,
        prior_specs = prior_specs,
        prior_label = self.loc:t("series_prior_books_header") or "── Prior Books ──",
        sort_desc = self.timeline_sort_desc,
        sort_label = self.timeline_sort_desc
            and (self.loc:t("timeline_sort_newest") or "Newest first")
            or (self.loc:t("timeline_sort_oldest") or "Oldest first"),
        on_sort_toggle = function()
            self.timeline_sort_desc = not self.timeline_sort_desc
            self:showTimeline()
        end,
        -- The chapter list belongs to the view, which does not exist while this
        -- table is being built. By the time a button can be tapped, it does.
        on_jump = function(where)
            local view = self.timeline_menu
            if view and view.jumpRowsTo then view:jumpRowsTo(where) end
        end,
        on_prior_toggle = function()
            self.series_prior_timeline_collapsed = not self.series_prior_timeline_collapsed
            self:showTimeline()
        end,
        show_parent = nil,
        on_back = function()
            if self.timeline_menu then UIManager:close(self.timeline_menu) end
        end,
        on_toggle = function(name)
            if name == nil then
                self.timeline_filter = {}
            else
                local kept, removed = {}, false
                for _, n in ipairs(self.timeline_filter) do
                    if n == name then removed = true else kept[#kept + 1] = n end
                end
                if not removed then kept[#kept + 1] = name end
                self.timeline_filter = kept
            end
            self:showTimeline()
        end,
    }

    local sw = Screen:getWidth()
    local pad = Screen:scaleBySize(10)
    local ScrollableContainer = require("ui/widget/container/scrollablecontainer")
    local text_w = sw - pad * 2 - ScrollableContainer:getScrollbarWidth()
    local face = Font:getFace("cfont", 17)

    -- Fixed row height lets the list size itself without laying out 365
    -- paragraphs. Measuring it needs a throwaway TextBoxWidget, so memoize.
    local line_h = _timelineLineHeight(face)
    local text_h = line_h * 3           -- heading plus two lines of summary
    local row_h = text_h + Screen:scaleBySize(14)

    local function openRow(spec)
        if spec and spec.ev then
            self:showTimelineEventDetails(spec.ev, { source = "menu" })
        end
    end

    -- Both lists render the same kind of row. They differ only in their contents
    -- and in whether a scrollbar takes width the rows would otherwise use.
    local function rowList(specs, scrolls)
        return XRayTimelineRowList:new{
            specs = specs,
            width = sw - (scrolls and ScrollableContainer:getScrollbarWidth() or 0),
            text_width = text_w,
            row_height = row_h,
            text_height = text_h,
            left_pad = pad,
            face = face,
            on_hold_row = openRow,
        }
    end

    local rows = rowList(row_specs, true)

    if prior_specs and not self.series_prior_timeline_collapsed then
        header_ctx.prior_list = rowList(prior_specs, #prior_specs > PRIOR_VISIBLE_ROWS)
        header_ctx.prior_view_height = row_h * math.min(#prior_specs, PRIOR_VISIBLE_ROWS)
    end

    if self.timeline_menu then
        self._timeline_rebuilding = true
        UIManager:close(self.timeline_menu)
        self._timeline_rebuilding = nil
        self.timeline_menu = nil
    end
    self.timeline_menu = XRayTimelineView:new{
        ui_instance = self,
        header_ctx = header_ctx,
        rows = rows,
    }
    UIManager:show(self.timeline_menu)
end

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
                local ok, err = pcall(function()
                    self.ai_helper:saveSettings({
                        timeline_presence_map = not self:presenceMapEnabled() })
                    -- Rebuild if the Timeline is open behind this menu.
                    if self.timeline_menu then self:showTimeline() end
                end)
                if not ok then
                    logger.warn("xray-timeline-patch: presence map toggle failed: "
                        .. tostring(err))
                end
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
    -- The ported view calls utils:flattenTOC, which older plugin versions lack;
    -- probe it so an incompatible install degrades with one named warning.
    local utils = pluginRequire("xray_utils")
    if type(utils) ~= "table" or type(utils.flattenTOC) ~= "function" then
        return "method xray_utils.flattenTOC"
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
