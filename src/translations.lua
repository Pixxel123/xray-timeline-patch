-- 2 timeline keys x 17 languages, maintained here in-repo (not generated):
-- the plugin's .po files carry neither msgid, the fork branch that added them
-- being gone, so tools/extract_translations.lua can regenerate this table
-- only from a languages dir that has both. Every string below is what the
-- plugin's own .po parse would produce, byte for byte.
return {
    ["ar"] = {
        ["menu_timeline_all"] = "الكل",
        ["menu_timeline_presence_map"] = "استخدام خريطة الحضور في الخط الزمني",
    },
    ["de"] = {
        ["menu_timeline_all"] = "Alle",
        ["menu_timeline_presence_map"] = "Präsenzkarte in der Zeitleiste verwenden",
    },
    ["en"] = {
        ["menu_timeline_all"] = "All",
        ["menu_timeline_presence_map"] = "Use Presence Map in Timeline",
    },
    ["es"] = {
        ["menu_timeline_all"] = "Todos",
        ["menu_timeline_presence_map"] = "Usar mapa de presencia en la cronología",
    },
    ["fr"] = {
        ["menu_timeline_all"] = "Tous",
        ["menu_timeline_presence_map"] = "Utiliser la carte de présence dans la chronologie",
    },
    ["hu"] = {
        ["menu_timeline_all"] = "Mind",
        ["menu_timeline_presence_map"] = "Jelenléti térkép használata az idővonalon",
    },
    ["id"] = {
        ["menu_timeline_all"] = "Semua",
        ["menu_timeline_presence_map"] = "Gunakan peta kehadiran di lini masa",
    },
    ["it"] = {
        ["menu_timeline_all"] = "Tutti",
        ["menu_timeline_presence_map"] = "Usa la mappa delle presenze nella cronologia",
    },
    ["ja"] = {
        ["menu_timeline_all"] = "すべて",
        ["menu_timeline_presence_map"] = "タイムラインで登場マップを使用",
    },
    ["nl"] = {
        ["menu_timeline_all"] = "Alle",
        ["menu_timeline_presence_map"] = "Aanwezigheidskaart in tijdlijn gebruiken",
    },
    ["pl"] = {
        ["menu_timeline_all"] = "Wszystkie",
        ["menu_timeline_presence_map"] = "Użyj mapy obecności na osi czasu",
    },
    ["pt_br"] = {
        ["menu_timeline_all"] = "Todos",
        ["menu_timeline_presence_map"] = "Usar mapa de presença na linha do tempo",
    },
    ["ru"] = {
        ["menu_timeline_all"] = "Все",
        ["menu_timeline_presence_map"] = "Использовать карту присутствия на шкале времени",
    },
    ["sr"] = {
        ["menu_timeline_all"] = "Сви",
        ["menu_timeline_presence_map"] = "Користи мапу присуства на временској оси",
    },
    ["tr"] = {
        ["menu_timeline_all"] = "Tümü",
        ["menu_timeline_presence_map"] = "Zaman çizelgesinde varlık haritasını kullan",
    },
    ["uk"] = {
        ["menu_timeline_all"] = "Усі",
        ["menu_timeline_presence_map"] = "Використовувати карту присутності на шкалі часу",
    },
    ["zh_CN"] = {
        ["menu_timeline_all"] = "全部",
        ["menu_timeline_presence_map"] = "在时间线中使用出场图",
    },
}
