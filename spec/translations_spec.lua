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
