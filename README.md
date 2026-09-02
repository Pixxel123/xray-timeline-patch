# xray-timeline-patch

A [KOReader user patch](https://github.com/koreader/koreader/wiki/User-patches)
for the [X-Ray plugin](https://github.com/ultimatejimmy/xray.koplugin) that
replaces the plot-timeline menu with a scrolling view topped by a **character
presence map**: one row per character, one column per chapter, marked wherever
that character appears. Tap one character to filter chapters; tap two to find
the chapters they share. Includes a sort-direction toggle, jump-to-end
chevrons, and a collapsible block for prior books in a series.

Runs entirely as a patch: no fork, no plugin replacement, and removing one
file restores the stock timeline.

## Install

1. Download `2-xray-timeline-presence-map.lua` from the
   [latest release](../../releases/latest).
2. Copy it into `koreader/patches/` (create the folder next to your
   KOReader settings if it doesn't exist).
3. Restart KOReader and open **X-Ray → Plot Timeline**.

Toggle the map under the new **Use Presence Map in Timeline** entry at the
bottom of the X-Ray menu.

## Compatibility

- X-Ray plugin **26.7.27** or newer; KOReader **2026.07** or newer (tested).
- On an incompatible plugin version the patch logs one warning and leaves
  the stock timeline untouched — it degrades, it doesn't crash.
- Translated into the plugin's 17 languages.

## Limitations

- The F-Droid build of KOReader does not run user patches; use the release
  APK (`org.koreader.launcher`).
- While installed, the patch supersedes the plugin's own timeline screen,
  including future upstream improvements to it.

## Development

Tests: `luajit tools/spec_runner.lua` (self-contained runner, no luarocks).
The installable file is **generated** — edit `src/`, then `luajit
tools/build.lua`; CI fails if the committed artifact drifts from `src/`.

Syncing from the development branch (`timeline-presence-map` on the plugin
fork): copy `xray_presencemap.lua` and its spec verbatim; re-splice the
`showTimeline` region into `src/patch_main.lua` between the REGION markers,
re-applying the three adaptations documented there (field name
`timeline_menu`, inlined `Presence`, `pluginRequire`); re-run
`tools/extract_translations.lua` if keys changed; rebuild.
