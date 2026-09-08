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

- Characters named in at least two chapters get a row, most-present first (a
  protagonist is kept regardless, and the cut is skipped when it would leave
  fewer than three rows). Four rows are visible; swipe up and down inside the
  map for more.
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
