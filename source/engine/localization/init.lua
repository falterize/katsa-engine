-- Localization: string tables per language, a current locale, fallback, plurals and `{name}`
-- parameters.
--
--   local L = Localization.get()                       -- the shared service
--   L:loadDirectory(resources, 'shared://locales')     -- en.lua, ru.lua ...
--   L:setLocale('ru')
--   L:t('menu.play')                                   -- 'Играть'
--   L:t('items', { count = 5 })                        -- plural form + {count} filled in
--
-- A locale file returns { name = 'Русский', strings = { menu = { play = 'Играть' } } }. Strings
-- are nested tables (read as dotted keys: 'menu.play') or flat. A table holding `other` is a
-- plural set: { one = '{count} предмет', few = ..., many = ..., other = ... }, chosen by
-- `params.count`. A missing key falls back to the fallback locale, then to the key itself (also
-- recorded in `getMissing()` so untranslated text is easy to find).
--
-- Label, Button and TextBox translate by themselves: set `textKey` (and `textParams`) and the
-- text follows the locale. `onChange` tells scripts about a locale switch.
local Plurals = require('./plurals')

local Localization = {}
Localization.__index = Localization

local shared

local function flatten(strings, prefix, out)
    for key, value in pairs(strings) do
        local path = prefix and (prefix .. '.' .. key) or tostring(key)
        if type(value) == 'table' and value.other == nil then
            flatten(value, path, out)
        else
            out[path] = value
        end
    end
    return out
end

function Localization.new(options)
    options = options or {}
    return setmetatable({
        fallback = options.fallback or 'en',
        locale = options.fallback or 'en',
        tables = {},
        meta = {},
        listeners = {},
        missing = {},
        revision = 1,
    }, Localization)
end

-- The service shared by the whole game (created on first use).
function Localization.get()
    shared = shared or Localization.new()
    return shared
end

-- Replaces the shared service; tests and tools use it to start clean.
function Localization.reset(service)
    shared = service
    return shared
end

-- Adds (or replaces) the strings of a locale. `meta` is free data such as { name = ..., font = ... }.
function Localization:addStrings(locale, strings, meta)
    assert(type(locale) == 'string' and locale ~= '', 'A locale needs a code such as en or ru')
    self.tables[locale] = flatten(strings, nil, {})
    self.meta[locale] = meta or self.meta[locale] or {}
    self.revision = self.revision + 1
end

-- Reads one locale file through the scene resources; the file name (en.lua) is the locale code
-- unless `locale` is given.
function Localization:loadFile(resources, path, locale)
    local text = assert(katsa.filesystem.read(resources:canonical(path)), 'Missing locale file: ' .. path)
    local chunk = assert(loadstring(text, '@' .. path))
    local data = assert(chunk())
    locale = locale or assert(path:match('([^/\\]+)%.lua$'), 'Locale file must be named <code>.lua')
    self:addStrings(locale, data.strings or data, { name = data.name, font = data.font })
    self.files = self.files or {}
    self.files[locale] = { resources = resources, path = path }
    return locale
end

-- Loads every <code>.lua of a folder. Returns the codes.
function Localization:loadDirectory(resources, directory)
    local codes = {}
    local canonical = resources:canonical(directory)
    for _, name in ipairs(katsa.filesystem.getDirectoryItems(canonical)) do
        local code = name:match('^([%w_%-]+)%.lua$')
        if code then
            codes[#codes + 1] = self:loadFile(resources, directory .. '/' .. name, code)
        end
    end
    table.sort(codes)
    return codes
end

-- Reads the file of a locale again (for hot-reload). Returns false when it was not loaded from a file.
function Localization:reload(locale)
    local file = self.files and self.files[locale]
    if not file then
        return false
    end
    self:loadFile(file.resources, file.path, locale)
    self:_notify()
    return true
end

-- Reloads the locale that was read from this file path (canonical, as the watcher sees it).
function Localization:reloadPath(path)
    for locale, file in pairs(self.files or {}) do
        if file.resources:canonical(file.path) == path then
            return self:reload(locale)
        end
    end
    return false
end

function Localization:locales()
    local list = {}
    for code in pairs(self.tables) do
        list[#list + 1] = code
    end
    table.sort(list)
    return list
end

function Localization:hasLocale(code)
    return self.tables[code] ~= nil
end

function Localization:getMeta(locale)
    return self.meta[locale or self.locale] or {}
end

-- Best loaded match for a code: "ru_RU.UTF-8" finds ru_RU, then ru.
function Localization:match(code)
    if not code then
        return nil
    end
    code = code:gsub('%..*$', ''):gsub('@.*$', ''):gsub('-', '_')
    if self.tables[code] then
        return code
    end
    local language = code:match('^(%a+)')
    return language and self.tables[language:lower()] and language:lower() or nil
end

-- Picks the locale the system asks for (LC_ALL / LANG), or the fallback when none is loaded.
function Localization:detect()
    local code = os.getenv('LC_ALL') or os.getenv('LC_MESSAGES') or os.getenv('LANG')
    return self:match(code) or self.fallback
end

function Localization:_notify()
    self.revision = self.revision + 1
    for _, listener in ipairs(self.listeners) do
        listener(self.locale)
    end
end

-- Switches the language; returns false (and keeps the old one) when it is not loaded.
function Localization:setLocale(code)
    local found = self:match(code)
    if not found then
        return false
    end
    if found ~= self.locale then
        self.locale = found
        self:_notify()
    end
    return true
end

function Localization:getLocale()
    return self.locale
end

-- Calls fn(locale) after every switch or reload. Returns a function that removes the listener.
function Localization:onChange(fn)
    self.listeners[#self.listeners + 1] = fn
    return function()
        for i, listener in ipairs(self.listeners) do
            if listener == fn then
                table.remove(self.listeners, i)
                return
            end
        end
    end
end

local function raw(self, locale, key)
    local strings = self.tables[locale]
    return strings and strings[key]
end

function Localization:exists(key, locale)
    return raw(self, locale or self.locale, key) ~= nil
end

local function fill(text, params)
    return (text:gsub('{([%w_]+)}', function(name)
        local value = params[name]
        return value ~= nil and tostring(value) or nil
    end))
end

-- Text for a key in the current locale. `params` fills {name} marks; `params.count` picks the
-- plural form.
function Localization:translate(key, params)
    local locale = self.locale
    local value = raw(self, locale, key)
    if value == nil then
        value, locale = raw(self, self.fallback, key), self.fallback
    end
    if value == nil then
        self.missing[key] = true
        return key
    end
    if type(value) == 'table' then
        local count = params and tonumber(params.count) or 0
        value = value[Plurals.category(locale, count)] or value.other
    end
    return params and fill(value, params) or value
end
Localization.t = Localization.translate

-- Keys that were asked for and found nowhere (sorted).
function Localization:getMissing()
    local list = {}
    for key in pairs(self.missing) do
        list[#list + 1] = key
    end
    table.sort(list)
    return list
end

-- Text of a node with `textKey`: cached until the locale changes (nodes with `textParams` are
-- translated each time because the table may change in place).
function Localization:resolve(node)
    local key = node.textKey
    if node.textParams == nil and node._locRevision == self.revision and node._locKey == key then
        return node._locText
    end
    local text = self:translate(key, node.textParams)
    node._locRevision, node._locKey, node._locText = self.revision, key, text
    return text
end

return Localization
