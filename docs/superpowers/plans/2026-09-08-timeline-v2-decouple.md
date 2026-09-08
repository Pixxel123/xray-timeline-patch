# Timeline v2 (decoupled presence strip) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn the patch from a full replacement of the X-Ray timeline screen into a presence strip plus character filter attached to the plugin's own beta timeline overlay.

**Architecture:** The patch no longer touches `showTimeline`. It wraps three class methods of the plugin's `EntityListOverlay` (`prepareItems`, `buildUI`, `onCloseWidget`) and only acts in timeline mode. A new UI-free-of-plugin-knowledge module builds the strip widget, caches its bitmaps and slots it into the stock widget tree by lending the stock layout a shorter screen height. The pure presence module keeps the matrix/order/match/bucket logic and gains always-visible rows plus two helpers.

**Tech Stack:** Lua 5.1 (LuaJIT), KOReader widget toolkit, KOReader `userpatch` hook, the repo's self-contained spec runner (`tools/spec_runner.lua`, no luarocks), concat build (`tools/build.lua`).

**Spec:** `docs/superpowers/specs/2026-09-08-timeline-v2-decouple-design.md` (same repo). Read it first; every task below argues from it.

## Global Constraints

- Work in the worktree `/home/mark/Programming/xray-timeline-patch/.claude/worktrees/decouple-ui` on branch `decouple-ui`. Call it `$W` below: `W=/home/mark/Programming/xray-timeline-patch/.claude/worktrees/decouple-ui`.
- LuaJIT: no system `luajit`; use KOReader's: `LUAJIT=$HOME/squashfs-root/usr/lib/koreader/luajit`. Run every spec/build command from `$W` (the runner and build use relative paths).
- Full suite: `cd $W && $LUAJIT tools/spec_runner.lua`. One file: `$LUAJIT tools/spec_runner.lua spec/<file>.lua`.
- Plugin floor: `26.9.4-beta` (first release shipping `xray_entity_list.lua`). Patch version `2.0.0`. Artifact filename stays `patches/2-xray-timeline-presence-map.lua`.
- Setting key `timeline_presence_map` (unset = on). Translation keys kept: `menu_timeline_presence_map`, `menu_timeline_all`. Keys deleted: `timeline_no_shared_chapters`, `timeline_sort_newest`, `timeline_sort_oldest`. 17 languages: `ar de en es fr hu id it ja nl pl pt_br ru sr tr uk zh_CN`.
- Filter state field on the plugin instance: `timeline_filter` (array of names). Per-overlay fields: `_presence` (data), `_presence_bitmaps` (cache), `_presence_widgets` (`names`, `scroller`, `all`).
- Geometry in KOReader scale units (`Screen:scaleBySize`): name gutter `floor(sw * 0.22)`, row 20, top padding 6, marker 9, label 9, min column 16, visible rows 4, caption 24, divider 1 plus span 4, side pad 6. Min chapter coverage 2.
- SVG classes: `cname`, `band` (fill `#e3e6df`), `shade` (fill `#d5d9cf`), `join`, `pip`.
- Commit messages use the repo's prefixes (`feat:`, `fix:`, `docs:`, `chore:`, `test:`). **No `Co-Authored-By` or `Claude-Session` trailers** in this repo (user rule).
- Do not hand-edit `patches/*.lua`; regenerate with `$LUAJIT tools/build.lua`. CI fails if the committed artifact drifts from `src/`.
- Never run `pkill -f` in these repos (it matches the agent's own shell).

---

## File structure

| File | Responsibility |
|---|---|
| `src/xray_presencemap.lua` (modify) | Pure logic: matrix, order, matches, buckets, SVG for names and grid, tap-row and caption helpers. No KOReader requires. |
| `src/xray_timeline_strip.lua` (create) | The strip widget: geometry, bitmap cache, name-gutter tap target, caption, scroll, divider; `insert` into the stock tree; `freeBitmaps`. Uses `Presence` (chunk-local from the build). Knows nothing about the plugin. |
| `src/patch_main.lua` (rewrite) | Adapter: plugin-module require helper, setting/translation helpers, per-overlay data, the three overlay wrappers, filter toggle, menu entry, capability check, registration. Uses `Presence`, `TRANSLATIONS`, `Strip`. |
| `src/translations.lua` (regenerate) | 2 keys × 17 languages. |
| `tools/build.lua` (modify) | Concatenate Presence + TRANSLATIONS + Strip + adapter; version/floor header. |
| `tools/extract_translations.lua` (modify) | `KEYS` trimmed to the two kept keys. |
| `tools/spec_runner.lua` (modify) | Spec list. |
| `spec/koreader_stubs.lua` (create) | Shared stand-ins for KOReader modules, used by the strip and hooks specs. |
| `spec/xray_presencemap_spec.lua` (modify) | SVG specs for always-visible rows; `rowAt`, `captionText`. |
| `spec/timeline_strip_spec.lua` (create) | Strip build/cache/tap/insert specs against `src/` directly. |
| `spec/patch_hooks_spec.lua` (create; replaces `spec/patch_smoke_spec.lua`) | Loads the built artifact under stubs; capability, filter, layout, tap, close, translations, menu. |
| `spec/translations_spec.lua` (modify) | 2 keys. |
| `README.md` (rewrite) | v2 behaviour, compatibility split, development notes. |
| `patches/2-xray-timeline-presence-map.lua` (regenerate) | The installable artifact. |

---

### Task 1: Presence SVG draws every row, highlights the selection

**Files:**
- Modify: `src/xray_presencemap.lua` (the `shownNames`, `buildStripNamesSVG`, `buildStripGridSVG` functions at the end of the file)
- Test: `spec/xray_presencemap_spec.lua` (the `split strip` describe block, currently lines 269-366)

**Interfaces:**
- Consumes: nothing new.
- Produces: `M.buildStripNamesSVG(order, selected, geom) -> svg, width, height` and `M.buildStripGridSVG(matrix, order, chapters, selected, geom, match_cols) -> svg, width, height`, both drawing all of `order`; `M.shownNames` removed. `M.stripHeight(n_rows, geom)` unchanged.

- [ ] **Step 1: Replace the two names-SVG selection tests and extend the grid tests**

In `spec/xray_presencemap_spec.lua`, inside `describe("buildStripNamesSVG", ...)`, replace the test `"writes only the selected names when filtering"` with:

```lua
            it("writes every name while filtering, bold on a band for the selected", function()
                local svg = presence.buildStripNamesSVG(order, { "Victor" }, GEOM)
                assert.is_not_nil(svg:find(">Walton<", 1, true))
                assert.equals(1, count(svg, "band"))
                assert.is_not_nil(svg:find('font%-weight="bold">Victor<'))
                assert.is_nil(svg:find('font%-weight="bold">Walton<'))
            end)

            it("keeps its height at one row per name whatever is selected", function()
                local _, _, h_all = presence.buildStripNamesSVG(order, {}, GEOM)
                local _, _, h_sel = presence.buildStripNamesSVG(order, { "Victor" }, GEOM)
                assert.equals(h_all, h_sel)
                assert.equals(presence.stripHeight(#order, GEOM), h_sel)
            end)
```

Inside `describe("buildStripGridSVG", ...)`, replace the test `"shades and joins the columns holding all selected characters"` with these three:

```lua
            it("shades and joins the columns holding all selected characters", function()
                local svg = presence.buildStripGridSVG(matrix, order, chapters, { "Creature", "Walton" }, GEOM,
                    presence.matchingChapters(matrix, { "Creature", "Walton" }))
                assert.equals(1, count(svg, "shade"))
                assert.equals(1, count(svg, "join"))
                assert.equals(2, count(svg, "band"))
            end)

            it("runs the join between the selected rows only", function()
                local svg = presence.buildStripGridSVG(matrix, order, chapters, { "Creature", "Walton" }, GEOM,
                    presence.matchingChapters(matrix, { "Creature", "Walton" }))
                local y1, y2 = svg:match('class="join" x1="[%d%.]+" y1="([%d%.]+)" x2="[%d%.]+" y2="([%d%.]+)"')
                -- rows 2 and 3: top_padding 6 + (row-1) * 19 + 19/2
                assert.equals("34.5", y1)
                assert.equals("53.5", y2)
            end)

            it("keeps every row's markers while filtering", function()
                local svg = presence.buildStripGridSVG(matrix, order, chapters, { "Victor" }, GEOM,
                    presence.matchingChapters(matrix, { "Victor" }))
                assert.equals(6, count(svg, "pip"))
                assert.equals(1, count(svg, "band"))
            end)
```

- [ ] **Step 2: Run the presence spec to see the new tests fail**

Run: `cd $W && $LUAJIT tools/spec_runner.lua spec/xray_presencemap_spec.lua`
Expected: FAIL. `writes every name while filtering...` fails on `>Walton<` (current code hides unselected rows); `keeps every row's markers...` fails with 4 pips; `runs the join...` fails because the join currently spans rows 1..2 of the filtered set.

- [ ] **Step 3: Rewrite the SVG builders**

In `src/xray_presencemap.lua`, delete the `M.shownNames` function (and its comment) and replace everything from `-- The left gutter:` down to the final `return M` with:

```lua
local function selectedSet(selected)
    local set = {}
    for _, name in ipairs(selected or {}) do set[name] = true end
    return set
end

-- The left gutter: one name per row, every row in `order`. Selected names
-- are bold on a shaded band. Split from the grid so it stays put while the
-- grid scrolls. Returns svg, width, height.
function M.buildStripNamesSVG(order, selected, geom)
    local is_selected = selectedSet(selected)
    local width, height = geom.name_width, M.stripHeight(#order, geom)
    local out = svgOpen(width, height)
    for r, name in ipairs(order) do
        local y = geom.top_padding + (r - 1) * geom.row_height + geom.row_height / 2
        if is_selected[name] then
            out[#out + 1] = string.format(
                '<rect class="band" x="0" y="%.1f" width="%d" height="%d" fill="#e3e6df"/>',
                y - geom.row_height / 2, width, geom.row_height)
        end
        out[#out + 1] = string.format(
            '<text class="cname" x="%.1f" y="%.1f" font-size="%d" text-anchor="end" fill="black"%s>%s</text>',
            width - 7, y + 3, geom.label_size + 2,
            is_selected[name] and ' font-weight="bold"' or "", xmlEscape(name))
    end
    out[#out + 1] = "</svg>"
    return table.concat(out, "\n"), width, height
end

-- The grid: columns as chapters (or bucketed spans), one row per name in
-- `order`. Returns svg, width, height.
--
-- Every row and every column stays while filtering, so the reader can see
-- where the matches fall against everyone else. Selected rows get a band,
-- matching columns a shade, and two or more selections a join line from the
-- first selected row to the last.
--
-- match_cols must be passed in. A bucketed matrix has already lost the
-- per-chapter detail, so the crossings cannot be worked out here.
function M.buildStripGridSVG(matrix, order, chapters, selected, geom, match_cols)
    local is_selected = selectedSet(selected)
    local filtering = selected ~= nil and #selected > 0

    local matches = {}
    for _, idx in ipairs(match_cols or {}) do matches[idx] = true end

    local nrows, ncols = #order, #chapters
    local width, height = ncols * geom.col_width, M.stripHeight(nrows, geom)
    local out = svgOpen(width, height)

    local function colX(i) return (i - 1) * geom.col_width + geom.col_width / 2 end
    local function rowY(r)
        return geom.top_padding + (r - 1) * geom.row_height + geom.row_height / 2
    end

    local first_sel, last_sel
    for r, name in ipairs(order) do
        if is_selected[name] then
            first_sel = first_sel or r
            last_sel = r
            out[#out + 1] = string.format(
                '<rect class="band" x="0" y="%.1f" width="%d" height="%d" fill="#e3e6df"/>',
                rowY(r) - geom.row_height / 2, width, geom.row_height)
        end
    end

    if filtering then
        local join = first_sel ~= nil and last_sel > first_sel
        for i = 1, ncols do
            if matches[i] then
                out[#out + 1] = string.format(
                    '<rect class="shade" x="%.1f" y="%.1f" width="%d" height="%.1f" fill="#d5d9cf"/>',
                    colX(i) - geom.col_width / 2, geom.top_padding - 4,
                    geom.col_width, nrows * geom.row_height + 4)
                if join then
                    out[#out + 1] = string.format(
                        '<line class="join" x1="%.1f" y1="%.1f" x2="%.1f" y2="%.1f" stroke="black" stroke-width="2"/>',
                        colX(i), rowY(first_sel), colX(i), rowY(last_sel))
                end
            end
        end
    end

    for r, name in ipairs(order) do
        for i = 1, ncols do
            if matrix[i] and matrix[i][name] then
                out[#out + 1] = string.format(
                    '<rect class="pip" x="%.1f" y="%.1f" width="%d" height="%d" fill="black"/>',
                    colX(i) - geom.marker / 2, rowY(r) - geom.marker / 2,
                    geom.marker, geom.marker)
            end
        end
    end

    out[#out + 1] = "</svg>"
    return table.concat(out, "\n"), width, height
end

return M
```

Also update the comment above `M.stripHeight` (it mentions the UI's scroll cap; keep the function body):

```lua
-- Pixel height of a strip with this many rows. Exported so the strip
-- widget's scroll viewport cannot drift from what the renderers draw.
function M.stripHeight(n_rows, geom)
    return geom.top_padding + n_rows * geom.row_height + 4
end
```

- [ ] **Step 4: Run the presence spec**

Run: `cd $W && $LUAJIT tools/spec_runner.lua spec/xray_presencemap_spec.lua`
Expected: all pass (was 43 specs; now 46). Then run the full suite: `$LUAJIT tools/spec_runner.lua` — the smoke spec still passes because the v1 region never reaches `shownNames` in the stubbed environment.

- [ ] **Step 5: Commit**

```bash
cd $W && git add src/xray_presencemap.lua spec/xray_presencemap_spec.lua
git commit -m "feat(presence): draw every row, band and bold the selection"
```

---

### Task 2: `rowAt` and `captionText` helpers

**Files:**
- Modify: `src/xray_presencemap.lua` (add before `return M`)
- Test: `spec/xray_presencemap_spec.lua` (add two describe blocks before the closing `end)` of the outer `describe("xray_presencemap", ...)`)

**Interfaces:**
- Produces: `M.rowAt(y_rel, geom, n_rows) -> integer|nil` (y relative to the strip image's top, in the same units as `geom`); `M.captionText(selected, n_matches) -> string` (`"A · B (N)"`, `""` for an empty selection).

- [ ] **Step 1: Write the failing tests**

Append inside the outer describe:

```lua
    describe("rowAt", function()
        local GEOM = { top_padding = 6, row_height = 19 }

        it("returns nil above the first row", function()
            assert.is_nil(presence.rowAt(5, GEOM, 3))
            assert.is_nil(presence.rowAt(-1, GEOM, 3))
        end)

        it("maps the first and last pixel of a row to that row", function()
            assert.equals(1, presence.rowAt(6, GEOM, 3))
            assert.equals(1, presence.rowAt(24, GEOM, 3))
            assert.equals(2, presence.rowAt(25, GEOM, 3))
            assert.equals(3, presence.rowAt(62, GEOM, 3))
        end)

        it("returns nil past the last row", function()
            assert.is_nil(presence.rowAt(63, GEOM, 3))
            assert.is_nil(presence.rowAt(200, GEOM, 3))
        end)

        it("returns nil for a non-number", function()
            assert.is_nil(presence.rowAt(nil, GEOM, 3))
        end)
    end)

    describe("captionText", function()
        it("joins the names with a middle dot and appends the count", function()
            assert.equals("Victor \u{00B7} Creature (9)", presence.captionText({ "Victor", "Creature" }, 9))
        end)

        it("is empty for an empty selection", function()
            assert.equals("", presence.captionText({}, 3))
            assert.equals("", presence.captionText(nil, 3))
        end)

        it("shows zero when nothing matches", function()
            assert.equals("Victor (0)", presence.captionText({ "Victor" }, 0))
            assert.equals("Victor (0)", presence.captionText({ "Victor" }, nil))
        end)
    end)
```

- [ ] **Step 2: Run to verify they fail**

Run: `cd $W && $LUAJIT tools/spec_runner.lua spec/xray_presencemap_spec.lua`
Expected: FAIL with `attempt to call field 'rowAt' (a nil value)` and the same for `captionText`.

- [ ] **Step 3: Implement**

Insert before `return M` in `src/xray_presencemap.lua`:

```lua
-- Which row a tap lands on. y_rel is measured from the top of the names
-- image, in the units geom uses. nil above the first row or past the last.
function M.rowAt(y_rel, geom, n_rows)
    if type(y_rel) ~= "number" or y_rel < geom.top_padding then return nil end
    local row = math.floor((y_rel - geom.top_padding) / geom.row_height) + 1
    if row < 1 or row > (n_rows or 0) then return nil end
    return row
end

-- The filter caption: names joined by a middle dot, then the number of
-- matching chapters in the stock title's "(N)" style, so it needs no
-- translated words. Empty when nothing is selected.
function M.captionText(selected, n_matches)
    if not selected or #selected == 0 then return "" end
    return table.concat(selected, " \u{00B7} ") .. " (" .. tostring(n_matches or 0) .. ")"
end
```

- [ ] **Step 4: Run to verify they pass**

Run: `cd $W && $LUAJIT tools/spec_runner.lua spec/xray_presencemap_spec.lua`
Expected: all pass (53 specs in this file).

- [ ] **Step 5: Commit**

```bash
cd $W && git add src/xray_presencemap.lua spec/xray_presencemap_spec.lua
git commit -m "feat(presence): rowAt and captionText helpers for the strip"
```

---

### Task 3: Trim translations to the two surviving keys

**Files:**
- Regenerate: `src/translations.lua`
- Modify: `tools/extract_translations.lua` (the `KEYS` table and the generated header line)
- Test: `spec/translations_spec.lua`

**Interfaces:**
- Produces: `TRANSLATIONS[lang][key]` for `key ∈ {menu_timeline_all, menu_timeline_presence_map}`, `lang` in the 17 codes.

- [ ] **Step 1: Update the translations spec**

Replace the whole of `spec/translations_spec.lua` with:

```lua
require("spec.spec_helper")

describe("translations", function()
    local KEYS = { "menu_timeline_all", "menu_timeline_presence_map" }
    local T = loadfile("src/translations.lua") and dofile("src/translations.lua") or {}

    it("covers all 17 languages", function()
        local n = 0
        for _ in pairs(T) do n = n + 1 end
        assert.are.equal(17, n)
        assert.is_true(T.en ~= nil)
        assert.is_true(T.pt_br ~= nil)
        assert.is_true(T.zh_CN ~= nil)
    end)

    it("has every key non-empty in every language", function()
        for lang, entries in pairs(T) do
            for _, key in ipairs(KEYS) do
                assert.is_true(type(entries[key]) == "string" and #entries[key] > 0,
                    tostring(lang) .. " missing " .. key)
            end
        end
    end)

    it("carries no dropped keys", function()
        for lang, entries in pairs(T) do
            local n = 0
            for _ in pairs(entries) do n = n + 1 end
            assert.are.equal(2, n, tostring(lang) .. " has extra keys")
        end
    end)

    it("keeps the English strings the code falls back to", function()
        assert.are.equal("All", T.en.menu_timeline_all)
        assert.are.equal("Use Presence Map in Timeline", T.en.menu_timeline_presence_map)
    end)
end)
```

- [ ] **Step 2: Run to see `carries no dropped keys` fail**

Run: `cd $W && $LUAJIT tools/spec_runner.lua spec/translations_spec.lua`
Expected: 1 failure, `carries no dropped keys` (5 keys present).

- [ ] **Step 3: Regenerate the table from the existing one**

The fork branch that supplied the `.po` entries no longer exists locally, so trim the committed table in place using the extractor's own serialisation format:

```bash
cd $W && $LUAJIT - <<'LUA'
local T = dofile("src/translations.lua")
local KEYS = { "menu_timeline_all", "menu_timeline_presence_map" }
local LANGUAGES = { "ar", "de", "en", "es", "fr", "hu", "id", "it", "ja",
                    "nl", "pl", "pt_br", "ru", "sr", "tr", "uk", "zh_CN" }
local out = {
    "-- Generated by tools/extract_translations.lua - DO NOT EDIT.",
    "-- 2 timeline keys x 17 languages, byte-identical to the plugin's .po parse.",
    "return {",
}
for _, lang in ipairs(LANGUAGES) do
    out[#out + 1] = string.format("    [%q] = {", lang)
    for _, key in ipairs(KEYS) do
        local value = assert(T[lang] and T[lang][key], lang .. " missing " .. key)
        out[#out + 1] = string.format("        [%q] = %q,", key, value)
    end
    out[#out + 1] = "    },"
end
out[#out + 1] = "}"
local f = assert(io.open("src/translations.lua", "w"))
f:write(table.concat(out, "\n"), "\n")
f:close()
print("wrote src/translations.lua")
LUA
```

Then in `tools/extract_translations.lua` set:

```lua
local KEYS = {
    "menu_timeline_all",
    "menu_timeline_presence_map",
}
```

and change the generated header line in the same file from `"-- 5 timeline keys x 17 languages, ..."` to `"-- 2 timeline keys x 17 languages, byte-identical to the plugin's .po parse."`.

- [ ] **Step 4: Run the translations spec and the full suite**

Run: `cd $W && $LUAJIT tools/spec_runner.lua spec/translations_spec.lua && $LUAJIT tools/spec_runner.lua`
Expected: translations 4/4 pass. The full suite has one failure in `patch_smoke_spec` (`injects translations absent-only` asserts `timeline_sort_oldest`). That spec is deleted in Task 5; do not fix it here.

- [ ] **Step 5: Commit**

```bash
cd $W && git add src/translations.lua tools/extract_translations.lua spec/translations_spec.lua
git commit -m "chore(i18n): keep only the menu label and All"
```

---

### Task 4: The strip module

**Files:**
- Create: `src/xray_timeline_strip.lua`
- Create: `spec/koreader_stubs.lua`
- Create: `spec/timeline_strip_spec.lua`
- Modify: `tools/build.lua` (concatenate the strip chunk)
- Modify: `tools/spec_runner.lua` (add the strip spec to the list)

**Interfaces:**
- Consumes: `Presence.buildStripNamesSVG`, `Presence.buildStripGridSVG`, `Presence.stripHeight`, `Presence.bucketMatrix`, `Presence.rowAt`, `Presence.captionText` (Tasks 1-2) via the chunk-local `Presence`.
- Produces (chunk-local `Strip` in the build):
  - `Strip.build(overlay, ctx) -> widget, height_px | nil, reason`. `ctx = { data = { matrix, order, chapters }, selected = {names}, matches = {row indices}, sw = px, all_label = string, on_toggle = function(name_or_nil), scroll = Geom|nil }`. Side effect: sets `overlay._presence_widgets = { names = InputContainer, scroller = ScrollableContainer|nil, all = Button|nil }` and `overlay._presence_bitmaps`.
  - `Strip.insert(overlay, widget, full_h) -> boolean`.
  - `Strip.freeBitmaps(overlay)`.
  - `Strip.VISIBLE_ROWS = 4`.

- [ ] **Step 1: Write the shared KOReader stubs**

Create `spec/koreader_stubs.lua`:

```lua
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
```

- [ ] **Step 2: Write the failing strip spec**

Create `spec/timeline_strip_spec.lua`:

```lua
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
local function run(fn)
    local captured, stubs = stubs_mod.make()
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

        it("adds a 24px caption with an All button while filtering", function()
            run(function(Strip)
                local overlay = {}
                local c = ctx(data(3), { "Victor" })
                local _, height = Strip.build(overlay, c)
                assert.equals(99, height)
                assert.is_table(overlay._presence_widgets.all)
                overlay._presence_widgets.all.callback()
                assert.equals("<all>", c.toggled[1])
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
            local vg = { align = "left", { name = "header" }, { name = "list" } }
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
```

Note `vg.reset`: the VerticalGroup stub's `resetLayout` sets it; the real VerticalGroup clears its cached `_size`.

- [ ] **Step 3: Register the spec and run it to see it fail**

In `tools/spec_runner.lua` change the list to:

```lua
local specs = {
    "spec/xray_presencemap_spec.lua",
    "spec/translations_spec.lua",
    "spec/timeline_strip_spec.lua",
    "spec/patch_smoke_spec.lua",
}
```

Run: `cd $W && $LUAJIT tools/spec_runner.lua spec/timeline_strip_spec.lua`
Expected: every test errors with `cannot open src/xray_timeline_strip.lua`.

- [ ] **Step 4: Write the strip module**

Create `src/xray_timeline_strip.lua`:

```lua
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
-- The mouse wheel arrives as a pan, and long-press belongs to the rows.
local IGNORED_GESTURES = { "pan", "pan_release", "hold", "hold_release", "hold_pan" }

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

local function captionRow(sw, text, all_button)
    local label = TextWidget:new{
        text = text,
        face = Font:getFace("cfont", 13),
        bold = true,
        fgcolor = Blitbuffer.COLOR_BLACK,
        max_width = sw - sc(40) - all_button:getSize().w,
    }
    local gap = math.max(sc(8), sw - sc(32) - label:getSize().w - all_button:getSize().w)
    return LeftContainer:new{
        dimen = Geom:new{ w = sw, h = sc(24) },
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
        overlay._presence_widgets = nil
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
            text_font_size = 13,
            padding = sc(2),
            bordersize = sc(1),
            radius = sc(4),
            callback = function() ctx.on_toggle(nil) end,
        }
        table.insert(parts, captionRow(sw,
            Presence.captionText(selected, #ctx.matches), widgets.all))
        height = height + sc(24)
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
```

- [ ] **Step 5: Run the strip spec**

Run: `cd $W && $LUAJIT tools/spec_runner.lua spec/timeline_strip_spec.lua`
Expected: 11 pass, 0 fail.

- [ ] **Step 6: Concatenate the strip into the build and rebuild**

In `tools/build.lua`, change the `out` table to:

```lua
local out = table.concat({
    header,
    "local Presence = (function()\n", slurp("src/xray_presencemap.lua"), "\nend)()\n\n",
    "local TRANSLATIONS = (function()\n", slurp("src/translations.lua"), "\nend)()\n\n",
    "local Strip = (function()\n", slurp("src/xray_timeline_strip.lua"), "\nend)()\n\n",
    slurp("src/patch_main.lua"),
})
```

Run: `cd $W && $LUAJIT tools/build.lua && $LUAJIT tools/spec_runner.lua`
Expected: `built patches/2-xray-timeline-presence-map.lua (... bytes)`. The whole suite passes again: the rebuilt artifact embeds the trimmed table, so the old smoke spec's translation assertion now compares nil with nil. (Task 5 replaces that spec.)

- [ ] **Step 7: Commit**

```bash
cd $W && git add src/xray_timeline_strip.lua spec/koreader_stubs.lua spec/timeline_strip_spec.lua tools/build.lua tools/spec_runner.lua patches/2-xray-timeline-presence-map.lua
git commit -m "feat(strip): presence strip widget with bitmap cache and stock-tree insertion"
```

---

### Task 5: Rewrite the adapter to decorate the stock overlay

**Files:**
- Rewrite: `src/patch_main.lua`
- Create: `spec/patch_hooks_spec.lua`
- Delete: `spec/patch_smoke_spec.lua`
- Modify: `tools/spec_runner.lua` (spec list)
- Regenerate: `patches/2-xray-timeline-presence-map.lua`

**Interfaces:**
- Consumes: `Strip.build/insert/freeBitmaps` (Task 4); `Presence.buildPresenceMatrix/coverageOrder/matchingChapters` (unchanged); `TRANSLATIONS` (Task 3).
- Produces on the plugin class: `presenceMapEnabled(self) -> boolean`, `settingEnabled(self, key, default)` (absent-only), wrapped `getSubMenuItems`. On the overlay class: wrapped `prepareItems`, `buildUI`, `onCloseWidget`. Plugin field `timeline_filter`.

- [ ] **Step 1: Write the failing hooks spec**

Create `spec/patch_hooks_spec.lua`:

```lua
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
                o:buildUI()
                assert.are.equal(1, #captured.warnings)
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
                -- the caption now takes 24px more
                assert.are.equal(800 - 99, o.seen_sh)
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
```

- [ ] **Step 2: Point the runner at the new spec and delete the smoke spec**

```bash
cd $W && git rm -q spec/patch_smoke_spec.lua
```

In `tools/spec_runner.lua`:

```lua
local specs = {
    "spec/xray_presencemap_spec.lua",
    "spec/translations_spec.lua",
    "spec/timeline_strip_spec.lua",
    "spec/patch_hooks_spec.lua",
}
```

Run: `cd $W && $LUAJIT tools/spec_runner.lua spec/patch_hooks_spec.lua`
Expected: failures throughout (the built artifact still carries the v1 adapter: `installs the setting...` fails on the overlay wrappers, `prepareItems` tests see 4 items with a filter set, etc.).

- [ ] **Step 3: Rewrite the adapter**

Replace the entire `src/patch_main.lua` with:

```lua
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
        if not isActive(self) then return orig(self, ...) end
        local data = ensureData(self)
        if #data.order == 0 or #data.chapters == 0 then return orig(self, ...) end

        -- The timeline can open from a gesture without the menu ever being
        -- built, so the "All" label is injected here too.
        injectTranslations(self.plugin)
        local filter = currentFilter(self, data)
        local widgets = self._presence_widgets
        local scroller = widgets and widgets.scroller
        local loc = self.plugin.loc
        local strip, height = Strip.build(self, {
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
            self._presence_widgets = nil
            return orig(self, ...)
        end
    end
end

local function wrapOnCloseWidget(Overlay)
    local orig = Overlay.onCloseWidget
    Overlay.onCloseWidget = function(self, ...)
        Strip.freeBitmaps(self)
        self._presence_widgets = nil
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

    XRayPlugin.presenceMapEnabled = presenceMapEnabled
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
```

- [ ] **Step 4: Rebuild and run the hooks spec, then the whole suite**

Run: `cd $W && $LUAJIT tools/build.lua && $LUAJIT tools/spec_runner.lua spec/patch_hooks_spec.lua && $LUAJIT tools/spec_runner.lua`
Expected: hooks spec 25 pass, 0 fail; full suite passes (presence 53 + translations 4 + strip 11 + hooks 25 = 93).

If `does not overwrite an existing settingEnabled` fails because `captured.fn` is set by the stub before `tweak` runs: `tweak` runs before `dofile`, so the replaced `registerPatchPluginFunc` is what the artifact calls. If it still fails, check that `stubs_mod.make()` builds `stubs.userpatch` fresh per call (it does).

- [ ] **Step 5: Commit**

```bash
cd $W && git add src/patch_main.lua spec/patch_hooks_spec.lua tools/spec_runner.lua patches/2-xray-timeline-presence-map.lua
git commit -m "feat: decorate the stock timeline overlay instead of replacing showTimeline"
```

---

### Task 6: Version, header, README, CI-equivalent check

**Files:**
- Modify: `tools/build.lua` (constants and header text)
- Rewrite: `README.md`
- Regenerate: `patches/2-xray-timeline-presence-map.lua`

**Interfaces:**
- Produces: the release artifact and docs for v2.0.0.

- [ ] **Step 1: Update the build constants and header**

In `tools/build.lua` replace the three constants and the header with:

```lua
local PATCH_VERSION = "2.0.0"
local PLUGIN_FLOOR  = "26.9.4-beta"   -- first release with xray_entity_list.lua, the timeline overlay

local header = string.format([[
-- xray-timeline-patch v%s
-- Character presence map and filter for the X-Ray plugin's plot timeline.
-- https://github.com/Pixxel123/xray-timeline-patch
-- Generated by tools/build.lua from src/. DO NOT EDIT DIRECTLY.
-- Requires: X-Ray plugin >= %s; KOReader >= 2026.07 (tested). On an
-- incompatible plugin this patch logs one warning and leaves the stock
-- timeline untouched; older plugins can use release v1.0.0.

]], PATCH_VERSION, PLUGIN_FLOOR)
```

Delete the `SOURCE_COMMIT` constant (it no longer applies).

- [ ] **Step 2: Rewrite the README**

Replace `README.md` with:

```markdown
# xray-timeline-patch

A [KOReader user patch](https://github.com/koreader/koreader/wiki/User-patches)
for the [X-Ray plugin](https://github.com/ultimatejimmy/xray.koplugin) that
adds a **character presence map** to the plugin's own plot-timeline screen:
one row per character, one column per chapter, marked wherever that
character appears. Tap a name to list only that character's chapters; tap a
second to find the chapters they share.

Everything else on the screen is the plugin's: search, paging, the
prior-books row and the event details. The plugin itself is never modified;
delete the file and the stock timeline is back.

## Install

1. Download `2-xray-timeline-presence-map.lua` from the
   [latest release](../../releases/latest).
2. Copy it into `koreader/patches/` (create the folder next to your
   KOReader settings if it doesn't exist).
3. Restart KOReader and open **X-Ray → Plot Timeline**.

Toggle the map under **Use Presence Map in Timeline** at the bottom of the
X-Ray menu.

## Using it

- Characters named in at least two chapters get a row, most-present first.
  Four rows are visible; swipe up and down inside the map for more.
- Tap a name to filter the list to that character's chapters. Tap another
  to keep only the chapters they share. Tap a selected name again to drop
  it, or **All** to clear the filter.
- The plugin's search box and the filter combine.
- On devices without a touch screen the map is shown but cannot be tapped.

## Compatibility

- X-Ray plugin **26.9.4-beta** or newer (the first version with the
  full-screen timeline); KOReader **2026.07** or newer (tested).
- On an older plugin the patch logs one warning and leaves the stock
  timeline untouched. For plugin versions 26.7.27 to 26.9.2-beta use
  [release v1.0.0](../../releases/tag/v1.0.0), which carries its own
  timeline screen.
- If a future plugin release changes the timeline's layout, the patch logs
  one warning and shows the plain stock list until it is updated.
- Translated into the plugin's 17 languages.

## Limitations

- The F-Droid build of KOReader does not run user patches; use the release
  APK (`org.koreader.launcher`).

## Development

Tests: `luajit tools/spec_runner.lua` (self-contained runner, no luarocks).
The installable file is generated: edit `src/`, then `luajit
tools/build.lua`; CI fails if the committed artifact drifts from `src/`.

Layout: `src/xray_presencemap.lua` is pure logic (matrix, order, SVG),
`src/xray_timeline_strip.lua` the strip widget, `src/patch_main.lua` the
adapter that wraps the plugin's `EntityListOverlay`. Design notes live in
`docs/superpowers/specs/`.
```

- [ ] **Step 3: Rebuild, run the suite, and check the artifact matches src exactly as CI would**

Run:

```bash
cd $W && $LUAJIT tools/build.lua && $LUAJIT tools/spec_runner.lua && git diff --stat patches/
```

Expected: `All tests passed successfully!`; the diff stat shows the artifact changed (its header now reads v2.0.0; it is committed next). Also sanity-check the artifact has no stale references:

```bash
cd $W && grep -n "shownNames\|timeline_sort\|timelineRowSpecs\|REGION" patches/2-xray-timeline-presence-map.lua src/*.lua; wc -l src/patch_main.lua
```

Expected: no matches; `src/patch_main.lua` under 300 lines.

- [ ] **Step 4: Commit**

```bash
cd $W && git add tools/build.lua README.md patches/2-xray-timeline-presence-map.lua
git commit -m "chore: release prep for v2.0.0 (floor 26.9.4-beta, README)"
```

---

### Task 7: Verify in the desktop AppImage against the beta, then push

**Files:**
- Create (throwaway, local-only, koreader repo): `/home/mark/Programming/koreader/dev/patches/2-zz-dev-timeline-shots.lua`
- Output: `/home/mark/Programming/koreader/dev/shots/*.png`

**Interfaces:**
- Consumes: the built artifact; the koreader checkout at upstream main (already fast-forwarded to e3708ff, link farm relinked); fixtures `rail-overflow`, `rail-bigcast`, `rail-series`; `./dev/dev.sh`.
- Produces: screenshots proving the strip, the filter, paging, scrolling and the prior-books behaviour; a pushed branch.

- [ ] **Step 1: Write the screenshot driver patch**

Create `/home/mark/Programming/koreader/dev/patches/2-zz-dev-timeline-shots.lua` (the `dev/` directory is excluded from git):

```lua
-- THROWAWAY dev tooling, never ship. Installed next to the real patch in
-- ~/.config/koreader/patches/ for one run. Once the reader is ready it
-- opens the X-Ray timeline, walks the presence strip with synthetic taps,
-- and writes one PNG per state to dev/shots/<XRAY_SHOT_PREFIX>-N.png.
local ok, userpatch = pcall(require, "userpatch")
if not ok or type(userpatch) ~= "table" or not userpatch.registerPatchPluginFunc then return end
local UIManager = require("ui/uimanager")
local Event = require("ui/event")
local Geom = require("ui/geometry")
local Screen = require("device").screen
local logger = require("logger")

local OUT = os.getenv("HOME") .. "/Programming/koreader/dev/shots/"
local PREFIX = os.getenv("XRAY_SHOT_PREFIX") or "run"

local function shot(name)
    local path = OUT .. PREFIX .. "-" .. name .. ".png"
    Screen:shot(path)
    logger.warn("dev-shots: wrote " .. path)
end

local function tap(x, y)
    UIManager:sendEvent(Event:new("Gesture",
        { ges = "tap", pos = Geom:new{ x = x, y = y, w = 0, h = 0 }, time = 0 }))
end

local function widgets(plugin)
    return plugin.timeline_menu and plugin.timeline_menu._presence_widgets
end

local function tapName(plugin, row)
    local w = widgets(plugin)
    local names = w and w.names
    if not (names and names.dimen) then logger.warn("dev-shots: no names widget"); return end
    local d = names.dimen
    tap(d.x + math.floor(d.w / 2),
        d.y + Screen:scaleBySize(6) + Screen:scaleBySize(20) * (row - 1) + Screen:scaleBySize(10))
end

local function clearAll(plugin)
    local w = widgets(plugin)
    if w and w.all and w.all.callback then w.all.callback() else logger.warn("dev-shots: no All button") end
end

local function scrollStrip(plugin)
    local w = widgets(plugin)
    local names = w and w.names
    if not (w and w.scroller and names and names.dimen) then
        logger.warn("dev-shots: strip does not scroll here"); return
    end
    local d = names.dimen
    UIManager:sendEvent(Event:new("Gesture", {
        ges = "swipe", direction = "north", distance = 200,
        pos = Geom:new{ x = d.x + d.w + 40, y = d.y + 30, w = 0, h = 0 }, time = 0 }))
end

userpatch.registerPatchPluginFunc("xray", function(XRayPlugin)
    local orig_ready = XRayPlugin.onReaderReady
    XRayPlugin.onReaderReady = function(self, ...)
        local result = orig_ready and orig_ready(self, ...)
        local steps = {
            function() self:showTimeline() end,
            function() shot("1-unfiltered") end,
            function() tapName(self, 1) end,
            function() shot("2-one-selected") end,
            function() tapName(self, 2) end,
            function() shot("3-two-selected") end,
            function() clearAll(self) end,
            function() shot("4-cleared") end,
            function() local m = self.timeline_menu; if m and m.onNextPage then m:onNextPage() end end,
            function() shot("5-page-two") end,
            function() scrollStrip(self) end,
            function() shot("6-strip-scrolled") end,
            function() local m = self.timeline_menu; if m and m.close then m:close() end end,
            function() shot("7-closed") end,
        }
        local i = 0
        local function step()
            i = i + 1
            local fn = steps[i]
            if not fn then logger.warn("dev-shots: done"); return end
            local ok2, err = pcall(fn)
            if not ok2 then logger.warn("dev-shots: step " .. i .. " failed: " .. tostring(err)) end
            UIManager:scheduleIn(2, step)
        end
        UIManager:scheduleIn(6, step)
        return result
    end
end)
```

- [ ] **Step 2: Record the current dev state so it can be restored**

```bash
cd /home/mark/Programming/koreader && mkdir -p dev/shots && grep -o '"auto_fetch_on_chapter":[a-z]*' ~/.config/koreader/settings/xray/settings.json; ls ~/Books/gutenberg-84.sdr/
```

Expected: the current `auto_fetch_on_chapter` value (note it), and whether `xray_cache.lua` / `xray_cache.lua.real` exist.

- [ ] **Step 3: Baseline run without the patch (stock beta)**

```bash
cd /home/mark/Programming/koreader && ./dev/dev.sh fixture rail-overflow && ./dev/dev.sh offline on
mv ~/.config/koreader/patches/2-xray-timeline-presence-map.lua ~/.config/koreader/patches/2-xray-timeline-presence-map.lua.off
cp dev/patches/2-zz-dev-timeline-shots.lua ~/.config/koreader/patches/
XRAY_SHOT_PREFIX=stock ./dev/dev.sh run ~/Books/gutenberg-84.epub
```

Wait for `dev/shots/stock-7-closed.png` to appear (use the Monitor tool on `ls dev/shots/stock-7-closed.png`, about 40 s), then `./dev/dev.sh stop`. Read `dev/shots/stock-1-unfiltered.png`. Expected: the stock overlay, title `Timeline (28)`, no strip.

- [ ] **Step 4: Run with the v2 patch on `rail-overflow`**

```bash
cd /home/mark/Programming/koreader && cp "$W/patches/2-xray-timeline-presence-map.lua" ~/.config/koreader/patches/ && rm -f ~/.config/koreader/patches/2-xray-timeline-presence-map.lua.off
XRAY_SHOT_PREFIX=overflow ./dev/dev.sh run ~/Books/gutenberg-84.epub
```

Wait for `overflow-7-closed.png`, then stop. Read all seven PNGs and check:
- `1-unfiltered`: stock header, then the strip (names right-aligned, 28 columns of pips, 4 rows: Victor Frankenstein, The Creature, Elizabeth Lavenza, Henry Clerval in some coverage order), then rows and the footer; fewer rows than the stock run.
- `2-one-selected`: first row bold on a band, caption `<name> (N)` with an **All** button, only that character's chapters listed.
- `3-two-selected`: two bands, shaded columns with a join line, list reduced further, caption names both.
- `4-cleared`: back to the unfiltered look.
- `5-page-two`: footer `Page 2 of N`, strip still present.
- `7-closed`: the book page, no overlay.
Then check the log. Find its path once with `grep -n '^LOG_FILE=' dev/dev.sh` (expand any variables it uses), then:

```bash
grep -n "xray-timeline-patch\|dev-shots\|traceback" <that log file>
```

Expected: no `xray-timeline-patch:` warnings, no tracebacks, seven `dev-shots: wrote` lines and one `dev-shots: done`.

- [ ] **Step 5: Run on `rail-bigcast` (strip scrolls) and `rail-series` (prior books)**

```bash
cd /home/mark/Programming/koreader && ./dev/dev.sh fixture rail-bigcast && XRAY_SHOT_PREFIX=bigcast ./dev/dev.sh run ~/Books/gutenberg-84.epub
```

Wait for `bigcast-7-closed.png`, stop. Check `bigcast-1-unfiltered.png` shows four rows with a scrollbar at the strip's right edge and bucketed columns, and `bigcast-6-strip-scrolled.png` shows different names in the strip while the list is unchanged.

```bash
cd /home/mark/Programming/koreader && ./dev/dev.sh fixture rail-series && XRAY_SHOT_PREFIX=series ./dev/dev.sh run ~/Books/gutenberg-84.epub
```

Wait, stop. Check `series-1-unfiltered.png` shows the stock **Prior Books in Series** row under the strip, and `series-2-one-selected.png` does not show it.

- [ ] **Step 6: Restore the dev environment**

```bash
cd /home/mark/Programming/koreader && ./dev/dev.sh stop; rm -f ~/.config/koreader/patches/2-zz-dev-timeline-shots.lua; ./dev/dev.sh fixture restore
```

If `auto_fetch_on_chapter` was `true` in Step 2, run `./dev/dev.sh offline off`. Leave the v2 patch installed in `~/.config/koreader/patches/` (it replaces the v1 copy that was there). Keep `dev/shots/` for the report.

- [ ] **Step 7: Fix anything the screenshots showed, then push**

If a screenshot contradicts the spec, fix it in `src/`, add or adjust a spec, rebuild, rerun the suite, amend into the relevant commit (`git commit --amend` is fine: nothing is PR'd yet), and rerun Step 4. When all checks pass:

```bash
cd $W && $LUAJIT tools/spec_runner.lua && $LUAJIT tools/build.lua && git status --short && git push -u origin decouple-ui
```

Expected: suite green, `git status` clean (the rebuild changed nothing), branch pushed. Do **not** tag or create the GitHub release; report the branch and leave those to the user.

---

## Self-review notes

- Spec coverage: hooks (Task 5), strip widget and insertion (Task 4), presence SVG changes and helpers (Tasks 1-2), translations (Task 3), capability check and floor (Task 5, Task 6 header), README and version (Task 6), manual verification incl. prior books, scrolling, paging, menu removal (Task 7), error handling table (Tasks 4-5 specs: render failure, bad tree, toggle throw, stock error re-raised).
- Type consistency: `Strip.build(overlay, ctx) -> widget, height | nil, reason`; `Strip.insert(overlay, strip, full_h) -> boolean`; `Strip.freeBitmaps(overlay)`; `Presence.rowAt(y_rel, geom, n_rows)`; `Presence.captionText(selected, n_matches)`; overlay fields `_presence`, `_presence_bitmaps`, `_presence_widgets.{names,scroller,all}`; plugin field `timeline_filter`; setting `timeline_presence_map`.
- Not in scope (spec): d-pad focus for the strip, sort/jump controls, persisting the filter across restarts, upstream hook proposal, the untracked fetch-window-guard patch.
