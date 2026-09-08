require("spec.spec_helper")
local stubs_mod = require("spec.koreader_stubs")

-- Victor in rows 1-3, Creature 2-3, Walton 3 only.
local MATRIX = {
    [1] = { Victor = true },
    [2] = { Victor = true, Creature = true },
    [3] = { Victor = true, Creature = true, Walton = true },
}
local NAMES = { "Victor", "Creature", "Walton", "Elizabeth", "Clerval", "Justine" }

local function data(n_names, n_chapters)
    local order, chapters, matrix = {}, {}, {}
    for i = 1, n_names do order[i] = NAMES[i] end
    for i = 1, (n_chapters or 3) do
        chapters[i] = "Chapter " .. i
        matrix[i] = MATRIX[i] or { Victor = true }
    end
    return { order = order, chapters = chapters, matrix = matrix }
end

local function ctx(d, selected, extra)
    local presence = _G.Presence
    local c = {
        data = d,
        selected = selected or {},
        matches = presence.matchingChapters(d.matrix, selected or {}),
        sw = 600,
        all_label = "All",
        toggled = {},
    }
    c.on_toggle = function(name) table.insert(c.toggled, name == nil and "<all>" or name) end
    for k, v in pairs(extra or {}) do c[k] = v end
    return c
end

-- Loads src/xray_timeline_strip.lua under stubs and runs fn(Strip, captured).
-- tweak(stubs) may adjust a stub before the module is loaded.
local function run(fn, tweak)
    local captured, stubs = stubs_mod.make()
    if tweak then tweak(stubs) end
    stubs_mod.with(stubs, function()
        _G.Presence = dofile("src/xray_presencemap.lua")
        local Strip = dofile("src/xray_timeline_strip.lua")
        fn(Strip, captured)
    end)
    _G.Presence = nil
end

describe("timeline strip", function()

    describe("build", function()

        it("returns a widget whose height covers rows, divider and gap", function()
            run(function(Strip, captured)
                local overlay = {}
                local strip, height = Strip.build(overlay, ctx(data(3)))
                assert.is_table(strip)
                -- 3 rows: 6 + 3*20 + 4 = 70, plus the 1px line and 4px span
                assert.equals(75, height)
                assert.equals(2, #captured.renders)
                assert.is_nil(overlay._presence_widgets.all)
                assert.is_nil(overlay._presence_widgets.scroller)
            end)
        end)

        it("adds a caption band tall enough for the All button while filtering", function()
            run(function(Strip)
                local overlay = {}
                local c = ctx(data(3), { "Victor" })
                local _, height = Strip.build(overlay, c)
                -- the 24px stub button plus 4px of breathing room, so its
                -- bottom border is inside the band the body is stacked under
                assert.equals(75 + 28, height)
                assert.is_table(overlay._presence_widgets.all)
                assert.equals(overlay, overlay._presence_widgets.all.show_parent)
                overlay._presence_widgets.all.callback()
                assert.equals("<all>", c.toggled[1])
            end)
        end)

        it("grows the caption band when the All button is taller", function()
            run(function(Strip)
                local overlay = {}
                local _, height = Strip.build(overlay, ctx(data(3), { "Victor" }))
                -- a 60px button needs a 64px band, not the 24px minimum
                assert.equals(75 + 64, height)
            end, function(stubs)
                stubs["ui/widget/button"] = {
                    new = function(_, t) t.getSize = function() return { w = 40, h = 60 } end; return t end,
                }
            end)
        end)

        it("caps the body at four rows and scrolls the rest", function()
            run(function(Strip)
                local overlay = {}
                local _, height = Strip.build(overlay, ctx(data(6)))
                -- viewport of 4 rows: 6 + 4*20 + 4 = 90, plus 5
                assert.equals(95, height)
                local scroller = overlay._presence_widgets.scroller
                assert.is_table(scroller)
                assert.equals(90, scroller.dimen.h)
                -- long-press belongs to the rows; drags and flicks scroll
                assert.are.same({ "hold", "hold_release", "hold_pan" }, scroller.ignore_events)
                assert.equals(overlay, scroller.show_parent)
            end)
        end)

        it("restores a saved scroll offset, clamped to the content", function()
            run(function(Strip)
                local overlay = {}
                Strip.build(overlay, ctx(data(6), {}, { scroll = { x = 0, y = 30 } }))
                assert.equals(30, overlay._presence_widgets.scroller.offset.y)
                Strip.freeBitmaps(overlay)
                Strip.build(overlay, ctx(data(6), {}, { scroll = { x = 0, y = 500 } }))
                -- content 6 rows = 130, viewport 90, so at most 40
                assert.equals(40, overlay._presence_widgets.scroller.offset.y)
            end)
        end)

        it("closes the previous scroller on rebuild", function()
            run(function(Strip)
                local overlay = {}
                Strip.build(overlay, ctx(data(6)))
                local first = overlay._presence_widgets.scroller
                assert.is_table(first)
                Strip.build(overlay, ctx(data(6)))
                local second = overlay._presence_widgets.scroller
                assert.is_true(first.closed)
                assert.is_true(first ~= second)
                assert.is_nil(second.closed)
            end)
        end)

        it("reuses the rendered bitmaps across rebuilds with the same filter", function()
            run(function(Strip, captured)
                local overlay = {}
                Strip.build(overlay, ctx(data(3)))
                Strip.build(overlay, ctx(data(3)))
                assert.equals(2, #captured.renders)
            end)
        end)

        it("re-renders and frees the old bitmaps when the filter changes", function()
            run(function(Strip, captured)
                local overlay = {}
                Strip.build(overlay, ctx(data(3)))
                local old = overlay._presence_bitmaps
                Strip.build(overlay, ctx(data(3), { "Victor" }))
                assert.equals(4, #captured.renders)
                assert.is_true(old.names.freed)
                assert.is_true(old.grid.freed)
                assert.is_true(overlay._presence_bitmaps ~= old)
            end)
        end)

        it("returns nil with a reason when rendering fails", function()
            run(function(Strip, captured)
                captured.render_fails = true
                local overlay = {}
                local strip, reason = Strip.build(overlay, ctx(data(3)))
                assert.is_nil(strip)
                assert.equals("strip render failed", reason)
                assert.is_nil(overlay._presence_widgets)
                assert.is_nil(overlay._presence_bitmaps)
            end)
        end)

        it("buckets a long book into the columns that fit", function()
            run(function(Strip, captured)
                local overlay = {}
                Strip.build(overlay, ctx(data(3, 200)))
                -- sw 600: viewport = 600 - 12 - floor(600*0.22)=132 = 456; 456/16 = 28 columns
                assert.equals(28 * math.floor(456 / 28), captured.renders[2].w)
            end)
        end)

        it("maps a tap on the name gutter to that row's name", function()
            run(function(Strip)
                local overlay = {}
                local c = ctx(data(3))
                Strip.build(overlay, c)
                local names = overlay._presence_widgets.names
                names:paintTo(nil, 0, 100)
                names:onTap(nil, { pos = { x = 5, y = 100 + 6 + 20 + 3 } })
                assert.equals("Creature", c.toggled[1])
                names:onTap(nil, { pos = { x = 5, y = 100 + 6 + 60 } })
                assert.equals(1, #c.toggled)
            end)
        end)

    end)

    describe("insert", function()

        local function stockTree(sh, n_children)
            -- Real KOReader builds this group through the class, so it
            -- carries resetLayout; the stub only attaches it via :new{}.
            local VerticalGroup = require("ui/widget/verticalgroup")
            local vg = VerticalGroup:new{ align = "left", { name = "header" }, { name = "list" } }
            if n_children == 3 then vg[3] = { name = "extra" } end
            return {
                [1] = { dimen = { w = 600, h = sh }, { height = sh, vg }, { dimen = { w = 600, h = sh } } },
                dimen = { x = 0, y = 0, w = 600, h = sh },
            }
        end

        it("slots the strip under the header and restores the full height", function()
            run(function(Strip)
                local overlay = stockTree(725, 2)
                local strip = { name = "strip" }
                assert.is_true(Strip.insert(overlay, strip, 800))
                local vg = overlay[1][1][1]
                assert.equals(3, #vg)
                assert.equals("header", vg[1].name)
                assert.equals(strip, vg[2])
                assert.equals("list", vg[3].name)
                assert.is_true(vg.reset)
                assert.equals(800, overlay[1][1].height)
                assert.equals(800, overlay[1].dimen.h)
                assert.equals(800, overlay[1][2].dimen.h)
                assert.equals(800, overlay.dimen.h)
            end)
        end)

        it("refuses a tree it does not recognise and leaves it alone", function()
            run(function(Strip)
                local overlay = stockTree(725, 3)
                assert.is_false(Strip.insert(overlay, { name = "strip" }, 800))
                assert.equals(3, #overlay[1][1][1])
                assert.equals(725, overlay[1][1].height)
                assert.is_false(Strip.insert({ [1] = {}, dimen = {} }, { name = "strip" }, 800))
                assert.is_false(Strip.insert({}, { name = "strip" }, 800))
            end)
        end)

    end)
end)
