-- Scene tags: every scene lists lowercase tags in its menu-settings.lua (`tags = { 'physics', '2d' }`).
-- The menu filters by selected tags (a scene needs all of them) and by search words (each word
-- must appear in the title, the id or a tag). A scene without `tags` falls back to its old
-- `category` as the only tag, so existing scene packages keep showing up.
local Tags = {}

function Tags.of(menu)
    local list = {}
    local seen = {}
    for _, tag in ipairs(menu.tags or {}) do
        tag = tostring(tag):lower()
        if tag ~= '' and not seen[tag] then
            seen[tag] = true
            list[#list + 1] = tag
        end
    end
    if #list == 0 and menu.category then
        list[1] = tostring(menu.category):lower()
    end
    return list
end

-- Splits a search string into lowercase words.
function Tags.words(query)
    local words = {}
    for word in tostring(query or ''):lower():gmatch('%S+') do
        words[#words + 1] = word
    end
    return words
end

-- entry: { title, id, tags }. selected: set { tag = true }. words: from Tags.words.
function Tags.matches(entry, selected, words)
    local have = {}
    for _, tag in ipairs(entry.tags) do
        have[tag] = true
    end
    for tag in pairs(selected) do
        if not have[tag] then
            return false
        end
    end
    local title, id = entry.title:lower(), entry.id:lower()
    for _, word in ipairs(words) do
        local found = title:find(word, 1, true) or id:find(word, 1, true)
        if not found then
            for _, tag in ipairs(entry.tags) do
                if tag:find(word, 1, true) then
                    found = true
                    break
                end
            end
        end
        if not found then
            return false
        end
    end
    return true
end

-- Every tag used by the entries, most used first (ties alphabetical), with its scene count.
function Tags.collect(entries)
    local counts, order = {}, {}
    for _, entry in ipairs(entries) do
        for _, tag in ipairs(entry.tags) do
            if not counts[tag] then
                counts[tag] = 0
                order[#order + 1] = tag
            end
            counts[tag] = counts[tag] + 1
        end
    end
    table.sort(order, function(a, b)
        if counts[a] ~= counts[b] then
            return counts[a] > counts[b]
        end
        return a < b
    end)
    local list = {}
    for _, tag in ipairs(order) do
        list[#list + 1] = { tag = tag, count = counts[tag] }
    end
    return list
end

return Tags
