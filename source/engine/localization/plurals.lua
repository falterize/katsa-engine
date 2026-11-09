-- Plural categories (one, few, many, other) by language, following the CLDR rules that games
-- need most. Languages without a rule use English (one for exactly 1, else other).
local Plurals = {}

local function english(n)
    return n == 1 and 'one' or 'other'
end

local function slavic(n)
    local ten, hundred = n % 10, n % 100
    if n ~= math.floor(n) then
        return 'other'
    end
    if ten == 1 and hundred ~= 11 then
        return 'one'
    elseif ten >= 2 and ten <= 4 and (hundred < 12 or hundred > 14) then
        return 'few'
    end
    return 'many'
end

local function polish(n)
    local ten, hundred = n % 10, n % 100
    if n == 1 then
        return 'one'
    elseif n == math.floor(n) and ten >= 2 and ten <= 4 and (hundred < 12 or hundred > 14) then
        return 'few'
    elseif n == math.floor(n) then
        return 'many'
    end
    return 'other'
end

local function none()
    return 'other'
end

local rules = {
    en = english,
    de = english,
    es = english,
    it = english,
    pt = english,
    nl = english,
    sv = english,
    fr = function(n)
        return n >= 0 and n < 2 and 'one' or 'other'
    end,
    ru = slavic,
    uk = slavic,
    be = slavic,
    pl = polish,
    ja = none,
    zh = none,
    ko = none,
    vi = none,
    th = none,
    id = none,
    tr = english,
}

-- Category name for `count` in `locale` ("ru", "ru_RU" and "ru-RU" all use the Russian rule).
function Plurals.category(locale, count)
    local language = tostring(locale):match('^(%a+)') or 'en'
    return (rules[language:lower()] or english)(math.abs(count))
end

return Plurals
