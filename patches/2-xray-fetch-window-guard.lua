-- xray-fetch-window-guard: KOReader user patch for the X-Ray plugin (xray.koplugin).
--
-- The bug it works around:
--   After a book is finished, the plugin's whole-book background fetch stores
--   last_fetch_page = <last page>. Go back to re-read an earlier chapter and,
--   on every open, the auto-merge fetch asks
--   ChapterAnalyzer:getTextForAnalysis(ui, 20000, nil, current_page + 1, last_fetch_page)
--   for the text "since the last fetch". Its 60-page window cap is
--   math.max(start_page, current_page - 60), which only bounds a start page
--   *before* the reader. A start page *after* the reader passes through as a
--   reversed range, crengine sorts it and extracts everything in between in one
--   synchronous call, and the device sits frozen for minutes with nothing logged.
--
-- The fix:
--   A start page past the reader means there is nothing new to extract, so drop
--   it and let the analyzer use its normal 60-page window, exactly as it does
--   for a fresh fetch.
--
-- Install: copy to koreader/patches/ (next to any other 2-*.lua patch) and
-- restart KOReader. Logs one INFO line each time it intervenes.
-- Verified against xray.koplugin 26.8.27 on KOReader v2026.07.1.

local logger = require("logger")

local ok, userpatch = pcall(require, "userpatch")
if not ok or type(userpatch) ~= "table" or not userpatch.registerPatchPluginFunc then
    return
end

-- Resolve the require() prefix for the plugin's own modules. Plugin dirs sit
-- bare on package.path today (prefix ""), and this keeps working if that changes.
local function pluginRequire(mod)
    local prefix = ""
    for name in pairs(package.loaded) do
        local p = name:match("^(.*)xray_ui$")
        if p then prefix = p; break end
    end
    return require(prefix .. mod)
end

userpatch.registerPatchPluginFunc("xray", function()
    local ok_mod, ChapterAnalyzer = pcall(pluginRequire, "xray_chapteranalyzer")
    if not ok_mod or type(ChapterAnalyzer) ~= "table"
            or type(ChapterAnalyzer.getTextForAnalysis) ~= "function" then
        logger.warn("xray-fetch-window-guard: ChapterAnalyzer.getTextForAnalysis not found, leaving the plugin untouched")
        return
    end
    if ChapterAnalyzer.__fetch_window_guard then return end
    ChapterAnalyzer.__fetch_window_guard = true

    local orig = ChapterAnalyzer.getTextForAnalysis
    ChapterAnalyzer.getTextForAnalysis = function(self, ui, max_len, progress_callback, current_page, start_page, ...)
        if type(start_page) == "number" and type(current_page) == "number"
                and start_page > current_page then
            logger.info("xray-fetch-window-guard: start page", start_page,
                "is past the reader at page", current_page, "- using the stock window instead")
            start_page = nil
        end
        return orig(self, ui, max_len, progress_callback, current_page, start_page, ...)
    end
end)
