-- Style engine of the uiStyler plugin.
--
-- Selectors (specificity in brackets; later rules win ties):
--   '*'               every node                      [0]
--   'uicorner'        a bare lowercase word is a tag   [10]  (style files: assets/styles)
--   'Button'          a class (isA, so 'Frame' matches buttons too)  [1]
--   '.primary'        a tag (node:addTag('primary'))  [10]
--   'Button.primary'  class and tag together          [11]
--   '#Search'         the node name                   [100]
-- Rule values: plain values, '$token' (theme lookup), a table whose strings are resolved
-- recursively, or function(tokens, node) -> value. Pseudo properties:
--   corner = n                   a UICorner modifier with radius n
--   stroke = { color, thickness, transparency }   a border UIStroke
-- A property the styler has set is restored to its authored value once no rule sets it.
local Tables = require('source.engine.core.tables')
local Styler = {}
Styler.__index = Styler

local function parse(selector)
    local class, tag, name = nil, nil, nil
    local specificity = 0
    if selector == '*' then
        return { specificity = 0 }
    end
    local id = selector:match('^#([%w_%-]+)$')
    if id then
        return { name = id, specificity = 100 }
    end
    if selector:match('^[%l_][%w_%-]*$') then
        return { tag = selector, specificity = 10 }
    end
    class, tag = selector:match('^([%w_]*)%.?([%w_%-]*)$')
    assert(class, 'Invalid selector: ' .. selector)
    if class ~= '' then
        specificity = specificity + 1
    else
        class = nil
    end
    if tag ~= '' and selector:find('.', 1, true) then
        specificity = specificity + 10
    else
        tag = nil
    end
    return { class = class, tag = tag, name = name, specificity = specificity }
end

local function matches(selector, node)
    if selector.name and node.name ~= selector.name then
        return false
    end
    if selector.class and not node:isA(selector.class) then
        return false
    end
    if selector.tag and not node:hasTag(selector.tag) then
        return false
    end
    return true
end

function Styler.new(ui, options)
    options = options or {}
    return setmetatable({
        ui = ui,
        themes = {},
        rules = {},
        roots = {},
        tokens = {},
        order = 0,
        styles = {},
    }, Styler)
end

function Styler:defineTheme(name, tokens)
    assert(type(name) == 'string' and type(tokens) == 'table', 'defineTheme(name, tokens)')
    self.themes[name] = tokens
    if self.themeName == name then
        self.tokens = tokens
    end
end

function Styler:rule(selector, properties)
    self.order = self.order + 1
    self.rules[#self.rules + 1] = {
        selector = parse(selector),
        text = selector,
        properties = properties,
        order = self.order,
    }
    table.sort(self.rules, function(a, b)
        if a.selector.specificity ~= b.selector.specificity then
            return a.selector.specificity < b.selector.specificity
        end
        return a.order < b.order
    end)
end

-- Registers one style: a selector plus a table that sets several values at once, e.g.
--   styler:style('uicorner', { corner = 10, cornerScale = 0.1, backgroundColor = '$panel' })
-- `extends = 'other'` (or a list) merges earlier styles first; own values win.
function Styler:style(selector, properties)
    self.styles[selector] = properties
    self:rule(selector, properties)
end

-- Loads every *.lua of a directory (e.g. scene assets/styles). A file returns either a map
-- { selector = { values } } or a list { { selector, { values } }, ... }.
function Styler:loadStyles(directory)
    local fs = katsa.filesystem
    local names = {}
    for _, filename in ipairs(fs.getDirectoryItems(directory)) do
        if filename:match('%.lua$') then
            names[#names + 1] = filename
        end
    end
    table.sort(names)
    for _, filename in ipairs(names) do
        local path = directory .. '/' .. filename
        local chunk = assert(fs.load(path))
        local data = chunk()
        assert(type(data) == 'table', path .. ' must return a table of styles')
        if data[1] ~= nil then
            for _, entry in ipairs(data) do
                self:style(entry[1], entry[2])
            end
        else
            local keys = {}
            for key in pairs(data) do
                keys[#keys + 1] = key
            end
            table.sort(keys)
            for _, key in ipairs(keys) do
                self:style(key, data[key])
            end
        end
    end
    return self
end

-- Flattens `extends` chains into one property table.
function Styler:expand(properties, depth)
    assert((depth or 0) < 8, 'Style extends chain is too deep')
    local base = properties.extends
    if base == nil then
        return properties
    end
    local merged = {}
    for _, name in ipairs(type(base) == 'table' and base or { base }) do
        local parent = assert(self.styles[name], 'Unknown style in extends: ' .. tostring(name))
        for key, value in pairs(self:expand(parent, (depth or 0) + 1)) do
            merged[key] = value
        end
    end
    for key, value in pairs(properties) do
        if key ~= 'extends' then
            merged[key] = value
        end
    end
    return merged
end

-- Replaces every rule with those of a style sheet: { { selector, properties }, ... }.
function Styler:sheet(rules)
    self.rules, self.styles = {}, {}
    for _, entry in ipairs(rules) do
        self:rule(entry[1], entry[2])
    end
end

function Styler:resolve(value, node)
    local kind = type(value)
    if kind == 'string' and value:sub(1, 1) == '$' then
        local key = value:sub(2)
        local token = self.tokens[key]
        assert(token ~= nil, ('Unknown theme token: %s (theme %s)'):format(value, tostring(self.themeName)))
        return Tables.copy(token)
    elseif kind == 'function' then
        return value(self.tokens, node)
    elseif kind == 'table' then
        local result = {}
        for key, item in pairs(value) do
            result[key] = self:resolve(item, node)
        end
        return result
    end
    return value
end

local function modifier(node, className, name)
    for _, child in ipairs(node.children) do
        if child.className == className and child._styler == name then
            return child
        end
    end
end

function Styler:setModifier(node, className, name, properties)
    local child = modifier(node, className, name)
    if not properties then
        if child then
            child:destroy()
        end
        return
    end
    if not child then
        child = self.ui:create(className, properties, node)
        child._styler = name
        return
    end
    for key, value in pairs(properties) do
        child[key] = value
    end
end

function Styler:styleNode(node)
    local record = node._styled or {}
    local wanted, corner, cornerScale, stroke = {}, nil, nil, nil
    for _, rule in ipairs(self.rules) do
        if matches(rule.selector, node) then
            for key, value in pairs(self:expand(rule.properties)) do
                if key == 'cornerScale' then
                    cornerScale = self:resolve(value, node)
                elseif key == 'corner' then
                    corner = self:resolve(value, node)
                elseif key == 'stroke' then
                    stroke = self:resolve(value, node)
                else
                    wanted[key] = value
                end
            end
        end
    end
    for key, value in pairs(wanted) do
        if record[key] == nil then
            record[key] = { authored = node[key] }
        end
        node[key] = self:resolve(value, node)
    end
    for key, saved in pairs(record) do
        if wanted[key] == nil then
            node[key] = saved.authored
            record[key] = nil
        end
    end
    node._styled = next(record) and record or nil
    if cornerScale ~= nil and corner == nil then
        corner = 0
    end
    if corner ~= nil or node._styledCorner then
        self:setModifier(
            node,
            'UICorner',
            'corner',
            corner ~= nil and { radius = { cornerScale or 0, corner } } or nil
        )
        node._styledCorner = corner ~= nil or nil
    end
    if stroke ~= nil or node._styledStroke then
        self:setModifier(node, 'UIStroke', 'stroke', stroke ~= nil and {
            target = 'Border',
            color = stroke.color,
            thickness = type(stroke.thickness) == 'table' and stroke.thickness
                or { 0, stroke.thickness or 1 },
            transparency = stroke.transparency or 0,
        } or nil)
        node._styledStroke = stroke ~= nil or nil
    end
end

local function visit(node, callback)
    callback(node)
    for _, child in ipairs(node.children) do
        if not child.modifier then
            visit(child, callback)
        end
    end
end

-- Styles a subtree (default: the UI content root) and remembers it for theme switches.
function Styler:apply(root)
    root = root or self.ui.content
    self.roots[root] = true
    visit(root, function(node)
        self:styleNode(node)
    end)
end

function Styler:setTheme(name)
    local tokens = assert(self.themes[name], 'Unknown theme: ' .. tostring(name))
    self.themeName, self.tokens = name, tokens
    for root in pairs(self.roots) do
        if root.destroyed then
            self.roots[root] = nil
        else
            self:apply(root)
        end
    end
    return name
end

function Styler:getTheme()
    return self.themeName
end

function Styler:themeNames()
    local names = {}
    for name in pairs(self.themes) do
        names[#names + 1] = name
    end
    table.sort(names)
    return names
end

return Styler
