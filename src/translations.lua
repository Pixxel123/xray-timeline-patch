-- 3 timeline keys x 17 languages, maintained here in-repo (not generated):
-- the plugin's .po files carry neither msgid, the fork branch that added them
-- being gone, so tools/extract_translations.lua can regenerate this table
-- only from a languages dir that has both. Every string below is what the
-- plugin's own .po parse would produce, byte for byte.
return {
    ["ar"] = {
        ["menu_timeline_all"] = "الكل",
        ["menu_timeline_presence_map"] = "استخدام خريطة الحضور في الخط الزمني",
        ["timeline_no_shared_chapters"] = "الشخصيات المحددة لا تشترك في أي فصل",
    },
    ["de"] = {
        ["menu_timeline_all"] = "Alle",
        ["menu_timeline_presence_map"] = "Präsenzkarte in der Zeitleiste verwenden",
        ["timeline_no_shared_chapters"] = "Die ausgewählten Figuren teilen sich kein Kapitel",
    },
    ["en"] = {
        ["menu_timeline_all"] = "All",
        ["menu_timeline_presence_map"] = "Use Presence Map in Timeline",
        ["timeline_no_shared_chapters"] = "Selected characters don't share any chapters",
    },
    ["es"] = {
        ["menu_timeline_all"] = "Todos",
        ["menu_timeline_presence_map"] = "Usar mapa de presencia en la cronología",
        ["timeline_no_shared_chapters"] = "Los personajes seleccionados no comparten ningún capítulo",
    },
    ["fr"] = {
        ["menu_timeline_all"] = "Tous",
        ["menu_timeline_presence_map"] = "Utiliser la carte de présence dans la chronologie",
        ["timeline_no_shared_chapters"] = "Les personnages sélectionnés ne partagent aucun chapitre",
    },
    ["hu"] = {
        ["menu_timeline_all"] = "Mind",
        ["menu_timeline_presence_map"] = "Jelenléti térkép használata az idővonalon",
        ["timeline_no_shared_chapters"] = "A kiválasztott szereplők nem szerepelnek közös fejezetben",
    },
    ["id"] = {
        ["menu_timeline_all"] = "Semua",
        ["menu_timeline_presence_map"] = "Gunakan peta kehadiran di lini masa",
        ["timeline_no_shared_chapters"] = "Karakter yang dipilih tidak berbagi bab apa pun",
    },
    ["it"] = {
        ["menu_timeline_all"] = "Tutti",
        ["menu_timeline_presence_map"] = "Usa la mappa delle presenze nella cronologia",
        ["timeline_no_shared_chapters"] = "I personaggi selezionati non compaiono nello stesso capitolo",
    },
    ["ja"] = {
        ["menu_timeline_all"] = "すべて",
        ["menu_timeline_presence_map"] = "タイムラインで登場マップを使用",
        ["timeline_no_shared_chapters"] = "選択したキャラクターは同じ章に登場しません",
    },
    ["nl"] = {
        ["menu_timeline_all"] = "Alle",
        ["menu_timeline_presence_map"] = "Aanwezigheidskaart in tijdlijn gebruiken",
        ["timeline_no_shared_chapters"] = "De geselecteerde personages delen geen hoofdstuk",
    },
    ["pl"] = {
        ["menu_timeline_all"] = "Wszystkie",
        ["menu_timeline_presence_map"] = "Użyj mapy obecności na osi czasu",
        ["timeline_no_shared_chapters"] = "Wybrane postacie nie występują w tym samym rozdziale",
    },
    ["pt_br"] = {
        ["menu_timeline_all"] = "Todos",
        ["menu_timeline_presence_map"] = "Usar mapa de presença na linha do tempo",
        ["timeline_no_shared_chapters"] = "Os personagens selecionados não compartilham nenhum capítulo",
    },
    ["ru"] = {
        ["menu_timeline_all"] = "Все",
        ["menu_timeline_presence_map"] = "Использовать карту присутствия на шкале времени",
        ["timeline_no_shared_chapters"] = "Выбранные персонажи не встречаются в одной главе",
    },
    ["sr"] = {
        ["menu_timeline_all"] = "Сви",
        ["menu_timeline_presence_map"] = "Користи мапу присуства на временској оси",
        ["timeline_no_shared_chapters"] = "Изабрани ликови се не појављују у истом поглављу",
    },
    ["tr"] = {
        ["menu_timeline_all"] = "Tümü",
        ["menu_timeline_presence_map"] = "Zaman çizelgesinde varlık haritasını kullan",
        ["timeline_no_shared_chapters"] = "Seçilen karakterler hiçbir bölümü paylaşmıyor",
    },
    ["uk"] = {
        ["menu_timeline_all"] = "Усі",
        ["menu_timeline_presence_map"] = "Використовувати карту присутності на шкалі часу",
        ["timeline_no_shared_chapters"] = "Вибрані персонажі не зустрічаються в одному розділі",
    },
    ["zh_CN"] = {
        ["menu_timeline_all"] = "全部",
        ["menu_timeline_presence_map"] = "在时间线中使用出场图",
        ["timeline_no_shared_chapters"] = "所选角色没有出现在同一章节",
    },
}
