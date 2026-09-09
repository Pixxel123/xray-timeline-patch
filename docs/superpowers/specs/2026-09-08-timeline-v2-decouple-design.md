# xray-timeline-patch v2 — decouple the UI from the stock timeline

Date: 2026-09-08
Status: implemented and released as v2.0.0 (2026-09-09)
Supersedes: v1.0.0 (full timeline replacement ported from fork commit c082f69)

## Goal

The X-Ray plugin's beta (26.9.4-beta, upstream commit c100d20 "Update UI for
main list screens") replaced the timeline's menu with a full-screen
`EntityListOverlay` (`xray_entity_list.lua`): header with search and close,
paginated 64-unit rows, a collapsible "Prior Books in Series" row, footer
paging with page jump, and d-pad focus zones. v1 of this patch replaces the
whole `showTimeline` method with an 840-line copy of a fork branch's view, so
every upstream timeline improvement is now hidden behind it.

v2 stops owning the timeline screen. The stock overlay is shown as-is; the
patch contributes only the **presence strip** (one row per character, one
column per chapter) and the **character filter**, attached to the overlay
through two wrapped class methods. Removing the patch file restores the stock
screen, as before.

## Decisions (made 2026-09-08)

| Decision | Choice |
|---|---|
| Placement | Inline strip between the stock header line and the first row (chosen over a separate map screen and over filter-only) |
| Character selection | Tap a name in the strip; no button grid |
| Rows shown | All characters with ≥ 2 chapters, coverage order; 4 rows visible, more scroll inside the strip |
| While filtering | Selected rows highlighted (bold name, shaded row); matching columns shaded with a join line between selected rows; unselected rows stay visible |
| Clearing | Tap a selected name again, or the "All" button in the caption |
| Caption | Only while filtering: `Holden · Naomi (9)` left, `All` right. Language-neutral: names plus a count in the stock title's `(N)` style |
| Dropped | Sort-direction toggle, jump-to-end chevrons, custom prior-books block, custom row list, custom title bar, "never share a chapter" message |
| Prior-book events | Listed by stock when not filtering; dropped from the list while filtering (they are not in the matrix, so they can never match) |
| Empty result | Stock "No items found"; the caption still names the filter |
| Floor | 26.9.4-beta (first release with `xray_entity_list`). Older plugins get one warning and the stock timeline; README points them at v1.0.0 |
| Source of truth | This repo. The fork-branch sync procedure and REGION markers are removed |
| Version | 2.0.0; artifact filename unchanged (`patches/2-xray-timeline-presence-map.lua`) so users replace one file |
| Release | v2.0.0 tagged from main; artifact filename unchanged so users replace one file |

## Runtime architecture

### What the patch file does at load

Unchanged from v1: `userpatch.registerPatchPluginFunc("xray", patch_fn)`.
`patch_fn(XRayPlugin)` runs once per plugin instance creation with the
plugin *class*; it is idempotent via `XRayPlugin.__timeline_patch_applied`.

`patch_fn`:

1. Runs the capability check (below). On failure: one `logger.warn`
   naming the missing piece, and return with nothing installed.
2. Installs on the plugin class, absent-only in both cases: `presenceMapEnabled(self)`
   (reads setting `timeline_presence_map`, unset = on) and `settingEnabled`
   (as v1).
3. Wraps `XRayPlugin.getSubMenuItems` to inject translations and append the
   menu entry (as v1). The entry's callback flips the setting and, if
   `self.timeline_menu` is open, calls stock `self:showTimeline()`, which
   closes and recreates the overlay.
4. Requires the overlay class via `pluginRequire("xray_entity_list")` and
   wraps three of its methods once (guard flag `__timeline_patch_applied`
   on the overlay class): `prepareItems`, `buildUI`, `onCloseWidget`
   (defined if absent).

`XRayPlugin.showTimeline` is **not** touched.

### Overlay data (per overlay instance)

`ensureData(overlay)` computes once per overlay and caches on the instance
(`overlay._presence`):

- `events`: entries of `overlay.raw_items` whose `source ~= "series_prior"`,
  in list order. Stock `showTimeline` has already run `assignTimelinePages`
  and `sortTimelineByTOC` on `plugin.timeline` before constructing the
  overlay, so the patch does not call them.
- `chapters`: `ev.chapter or ""` per event, same index.
- `matrix = Presence.buildPresenceMatrix(events, plugin.characters or {})`.
- `order = Presence.coverageOrder(matrix, characters, MIN_CHAPTER_COVERAGE=2)`.

The v1 plugin-level `_timeline_cache` is removed; a rebuild per overlay open
is cheap and avoids identity/signature bookkeeping.

Filter state stays on the plugin: `plugin.timeline_filter` (array of names),
so reopening the timeline keeps it. It is ignored while the setting is off.

### `prepareItems` wrapper

```
orig(self)                                   -- sets self.items (search applied, stock order)
if self.mode ~= "timeline" or not self.plugin
   or not self.plugin:presenceMapEnabled() then return end
local filter = self.plugin.timeline_filter or {}
if #filter == 0 then return end
local data = ensureData(self)
local keep = {}
for _, idx in ipairs(Presence.matchingChapters(data.matrix, filter)) do
    keep[data.events[idx]] = true                -- identity, not index
end
filter self.items in place: keep only items with keep[item]
```

Consequences: stock search and the character filter compose as AND; prior
events drop out (never in `keep`), so stock's `has_prior` check hides the
"Prior Books" row; the stock title count (`#raw_items`) is unchanged.

### `buildUI` wrapper

```
if not (timeline mode and plugin and enabled and #data.order > 0 and #data.chapters > 0) then
    return orig(self)
end
local strip, strip_h = buildStrip(self)      -- may be nil on render failure → orig(self)
local full_h = self.sh
self.sh = full_h - strip_h
local ok, err = pcall(orig, self)
self.sh = full_h
if not ok then error(err) end                -- stock failure is stock's problem; do not mask
if not insertStrip(self, strip, full_h) then
    warnOnce("overlay layout not recognised - showing the stock timeline without the map")
    strip:free(); return orig(self)          -- rebuild at full height, no strip
end
```

`insertStrip` verifies the duck-typed shape the beta builds and mutates it:

- `self[1]` is a table (OverlapGroup) with `dimen`, `[1]` (main surface
  FrameContainer with numeric `height` and `[1]` a VerticalGroup with exactly
  two children) and `[2]` (BottomContainer with `dimen`).
- `table.insert(vg, 2, strip)`; `vg:resetLayout()` if present.
- `self[1][1].height = full_h`; `self[1].dimen.h = full_h`;
  `self[1]._size = nil`; `self[1][2].dimen.h = full_h`; `self.dimen.h = full_h`.

Why shrink first: stock computes `items_per_page` from `sh - header_h -
footer_h`. Shrinking `sh` by the strip height makes stock budget the rows
correctly; restoring the heights afterwards puts the footer back at the real
screen bottom. The header + strip + rows then total at most `full_h - footer_h`.

The wrapper is re-entered on every stock rebuild (page turn, d-pad move, tap
on empty space, prior toggle). The strip is rebuilt each time from cached
bitmaps (below).

### The strip widget

Vertical stack, full width, inserted at index 2 of the main VerticalGroup:

1. **Caption** (only while filtering), height 24 units: left a `TextWidget`
   with bold selected names joined by ` · ` and ` (N)` where N = number of
   matching chapters; right a small `Button` labelled with the
   `menu_timeline_all` string that clears the filter.
2. **Body**: `HorizontalGroup{ HorizontalSpan(6u), names, grid }` where
   `names` is an `InputContainer` wrapping an `ImageWidget` of the names SVG
   and `grid` is an `ImageWidget` of the grid SVG. When `#order >
   STRIP_VISIBLE_ROWS (4)` the body sits in a `ScrollableContainer` of height
   `Presence.stripHeight(4, geom)` with `ignore_events = {"hold",
   "hold_release", "hold_pan"}`; its scroll offset is saved on the overlay
   (`_presence_scroll`) before a rebuild and restored after, as v1's
   `_restoreScroll` did.
3. **Divider**: 1-unit line, `Color8(180)`, inset 16 units, plus a 4-unit span.

Geometry (units = `Screen:scaleBySize`): `name_width = floor(sw * 0.22)`,
`row_height 20`, `top_padding 6`, `marker 9`, `label_size 9`; columns are
bucketed via `Presence.bucketMatrix` when `#chapters > floor(viewport_w / 16u)`,
exactly as v1.

Gesture routing: KOReader's `WidgetContainer:propagateEvent` offers a gesture
to children before the container's own `ges_events`, so the names
InputContainer gets taps and the ScrollableContainer gets vertical swipes
before the overlay's full-screen Tap/Swipe handlers. Horizontal swipes
outside the strip still page the list.

Tap → row: `row = floor((ges.pos.y - names.dimen.y - top_padding) / row_height) + 1`.
`names.dimen.y` is set by `paintTo` and already includes the scroll offset
(ScrollableContainer paints children at the shifted origin). `order[row]`
toggles in `plugin.timeline_filter`; then
`self.current_page = 1; self:prepareItems(); self:buildUI(); UIManager:setDirty(self, "ui")`.
A tap past the last row is ignored.

Bitmap cache: rendered `names_bb`/`grid_bb` are stored on the overlay
(`_presence_bitmaps`) keyed by `table.concat(filter, "\n") .. "|" .. sw`.
ImageWidgets are created with `image_disposable = false`. The cache is
freed when the key changes and in the wrapped `onCloseWidget`.

Rendering uses `RenderImage:renderImageData(svg, #svg, false, w, h)` at the
SVG's own size (as v1). If either render fails, `buildStrip` returns nil and
the stock UI is built untouched, with one `logger.warn`.

### Presence module changes (`src/xray_presencemap.lua`)

- `shownNames` is removed. `buildStripNamesSVG(order, selected, geom)` and
  `buildStripGridSVG(matrix, order, chapters, selected, geom, match_cols)`
  always draw every name in `order`.
- Selected rows: names SVG draws a full-width `rect` fill `#e3e6df` behind the
  row and the name in `font-weight="bold"`; grid SVG draws the same row band.
- Matching columns (while filtering): column `rect` fill `#d5d9cf` spanning
  all rows, drawn before pips; join `line` from the first to the last
  *selected* row index when two or more names are selected.
- New pure helpers: `M.rowAt(y_rel, geom, n_rows)` → row index or nil;
  `M.captionText(selected, n_matches)` → `"A · B (N)"`.
- `stripHeight`, `buildPresenceMatrix`, `coverageOrder`, `matchingChapters`,
  `bucketMatrix` unchanged.

### Capability check

All must hold, else one warning and nothing installed:

- `XRayPlugin.getSubMenuItems` and `XRayPlugin.showTimeline` are functions.
- `pluginRequire("xray_entity_list")` succeeds and returns a table whose
  `prepareItems` and `buildUI` are functions.
- `require("ui/renderimage")` succeeds (the strip is bitmaps).

`xray_theme`, `xray_utils.flattenTOC`, `assignTimelinePages`,
`sortTimelineByTOC`, `showTimelineEventDetails`, `log` are no longer required
by the patch and leave the check.

### Translations

`src/translations.lua` shrinks to two keys × 17 languages:
`menu_timeline_presence_map` and `menu_timeline_all`. The other three keys
are deleted from the table and from `KEYS` in `tools/extract_translations.lua`.
Injection stays absent-only. The fork branch that supplied the original
`.po` entries no longer exists locally, so the table is maintained in-repo;
the extractor remains for a future languages dir that carries these msgids.

## Repo layout after v2

```
src/xray_presencemap.lua     pure logic + SVG (modified as above)
src/translations.lua         2 keys × 17 languages
src/patch_main.lua           adapter: pluginRequire, ensureData, buildStrip,
                             insertStrip, wrappers, menu entry, capability
                             check, registration (~300 lines, no REGION markers)
tools/build.lua              PATCH_VERSION "2.0.0", PLUGIN_FLOOR "26.9.4-beta",
                             SOURCE_COMMIT removed, header text updated
tools/extract_translations.lua  KEYS trimmed
tools/spec_runner.lua        unchanged
spec/xray_presencemap_spec.lua  updated for always-visible rows, rowAt, captionText
spec/patch_hooks_spec.lua    replaces patch_smoke_spec.lua (below)
spec/translations_spec.lua   2 keys
patches/2-xray-timeline-presence-map.lua  regenerated
README.md                    rewritten
docs/superpowers/specs/      this file
```

## Testing

Runner: `luajit tools/spec_runner.lua` (self-contained; CI unchanged:
specs, rebuild, drift check).

`spec/patch_hooks_spec.lua` loads the **built artifact** under stubs (the v1
`withArtifact` pattern) and covers:

1. Registers for `"xray"`.
2. Missing `xray_entity_list` → one warning, class untouched, no menu entry.
3. Overlay module without `buildUI` → same degrade.
4. Capable class → `presenceMapEnabled` installed, menu entry appended with
   `checked_func`/`callback`, overlay methods wrapped exactly once across two
   `patch_fn` calls.
5. `prepareItems`: fixture plugin with `timeline` (current + prior events) and
   `characters`; no filter → items identical to stock; filter `{A}` → only
   events in A's chapters, by identity; prior events gone; other modes and
   disabled setting → untouched; search + filter compose.
6. `buildUI` with a fake overlay class whose stock `buildUI` builds the beta
   tree shape from `self.sh`: strip present at index 2 of the VerticalGroup,
   stock saw `sh - strip_h`, all four heights restored to full `sh`.
7. `buildUI` with an unrecognised tree: no strip, one warning, stock rebuilt
   at full height; the warning is not repeated on the next rebuild.
8. Render failure (stubbed `RenderImage` returns nil): stock UI untouched,
   one warning.
9. Tap mapping via `Presence.rowAt` and the names InputContainer's `onTap`:
   toggles the plugin filter, resets `current_page`, calls `prepareItems`
   and `buildUI`; a tap below the last row is a no-op; "All" clears.
10. `onCloseWidget` frees cached bitmaps (stub `free` counters).
11. Translations: absent-only, 2 keys, English fallback.

`spec/xray_presencemap_spec.lua`: existing matrix/order/match/bucket specs
unchanged; SVG specs updated (all names drawn, bold + band for selected,
column shade + join between selected row indices); new `rowAt` and
`captionText` specs.

Manual, in the desktop AppImage with the plugin at 26.9.4-beta and the built
patch copied into KOReader's `patches/` folder: open X-Ray → Plot Timeline with a
book that has timeline + characters; check strip below the header, 4 rows
+ scroll, tap filters and clears, page turns keep the strip, prior-books row
present unfiltered and absent while filtering, menu toggle removes/restores
the strip, no warnings in the log. Then remove the patch file and confirm
the stock screen.

## Error handling summary

| Failure | Behaviour |
|---|---|
| Plugin too old / module missing | one warning at load; stock everything |
| Overlay tree shape changed upstream | one warning per session; stock list, no strip |
| SVG render fails | one warning; stock list, no strip |
| Tap handler throws | `pcall`ed; logged; overlay unchanged |
| Stock `buildUI` throws | re-raised after restoring `sh` (not masked) |

## Out of scope

- D-pad focus for the strip (non-touch devices see the map, cannot filter).
- Re-adding a timeline sort or jump controls.
- Persisting the filter across KOReader restarts.
- Proposing an upstream hook (`buildExtraHeader`); may follow separately.
- The untracked `patches/2-xray-fetch-window-guard.lua` in the main checkout.

## Success criteria

- On plugin 26.9.4-beta the timeline is the stock overlay plus the strip; all
  stock controls work unchanged; filtering by one or two names lists exactly
  the matching chapters.
- On plugin ≤ 26.9.2-beta the patch logs one warning and the stock timeline
  is untouched.
- `src/patch_main.lua` ≤ ~350 lines with no copied stock UI.
- All specs green; CI drift check green; README describes v2 and the v1
  fallback for older plugins.
