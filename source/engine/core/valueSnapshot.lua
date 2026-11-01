local Array = require('source.engine.math.array')
local ipairs = require('source.engine.math.array').ipairs
local pairs = require('source.engine.math.array').pairs
-- Allocation-free snapshots for mutable authored values. Fixed schemas compile once.
local Managed = require('source.engine.math.managedValue')

local empty = {}

local function scalar(record, key, value)
    local changed = record[key] ~= value
    if changed then
        record[key] = value
    end
    return changed
end

local function vector(record, key, value)
    local versions = record._managedVersions
    if Managed.is(value) then
        versions = versions or {}
        record._managedVersions = versions
        local previous = versions[key]
        if previous and previous.value == value and previous.revision == value.revision then
            return false
        end
        previous = previous or {}
        versions[key] = previous
        previous.value, previous.revision = value, value.revision
    elseif versions then
        versions[key] = nil
    end
    if not Array.is(value) then
        return scalar(record, key, value)
    end
    value = Managed.read(value)
    local old = record[key]
    local changed = not Array.is(old) or #old ~= #value
    if not Array.is(old) then
        old = {}
        record[key] = old
    end
    local count = #value
    local previousCount = #old
    if count >= 2 and count <= 4 then
        -- Common authored vectors avoid nested short-loop traces. Nil slots and
        -- shrinking arrays retain the same snapshot semantics as the general path.
        if old[1] ~= value[1] then
            old[1], changed = value[1], true
        end
        if old[2] ~= value[2] then
            old[2], changed = value[2], true
        end
        if count >= 3 and old[3] ~= value[3] then
            old[3], changed = value[3], true
        end
        if count == 4 and old[4] ~= value[4] then
            old[4], changed = value[4], true
        end
    else
        for i = 1, count do
            if old[i] ~= value[i] then
                changed = true
                old[i] = value[i]
            end
        end
    end
    for i = previousCount, count + 1, -1 do
        old[i] = nil
    end
    return changed
end
-- Canonical engine fields do not need the public alias/setter dispatch on every read.
-- Keep typed values, class defaults and enabled getters equivalent to Node.__index.
local function value(node, key, class, typed, billboard, observed)
    if not class then
        return node[key]
    end
    if observed and observed[key] ~= nil then
        return observed[key]
    end
    if key == 'parent' then
        return node.parent
    end
    if typed and typed[key] ~= nil then
        return typed[key]
    end
    if billboard and billboard[key] then
        return billboard[key]
    end
    if key == 'enabled' and class.getEnabled then
        return node:getEnabled()
    end
    return class[key]
end
local checkers = {}

local function fields(record, node, keys, vectors)
    local group = checkers[keys]
    if not group then
        group = {}
        checkers[keys] = group
    end
    local vectorKey = vectors or empty
    local check = group[vectorKey]
    if not check then
        -- Compile fixed schemas once. This avoids nested polymorphic iterator traces
        -- and allocates no temporary field lists/snapshots in the steady-state scan.
        local code = {
            'return function(r,n) local changed=false; local v;',
            "local c=rawget(n,'_class'); local t=rawget(n,'_typedValues');",
            "local b=rawget(n,'_billboardVectors'); local o=rawget(n,'_observedValues');",
        }
        for _, key in ipairs(keys) do
            local k = string.format('%q', key)
            code[#code + 1] = 'v=rawget(n,'
                .. k
                .. ');if v==nil then v=value(n,'
                .. k
                .. ',c,t,b,o) end; if r['
                .. k
                .. ']~=v then r['
                .. k
                .. ']=v; changed=true end;'
        end
        for _, key in ipairs(vectorKey) do
            local k = string.format('%q', key)
            code[#code + 1] = 'v=rawget(n,'
                .. k
                .. ');if v==nil then v=value(n,'
                .. k
                .. ',c,t,b,o) end;'
                .. 'changed=vector(r,'
                .. k
                .. ',v) or changed;'
        end
        code[#code + 1] = 'return changed end'
        local chunk = assert(loadstring(table.concat(code, '\n'), 'renderState.schema'))
        setfenv(chunk, { value = value, vector = vector, rawget = rawget })
        check = chunk()
        group[vectorKey] = check
    end
    return check(record, node)
end

local function settings(record, source)
    local changed = false
    for key, value in pairs(source or empty) do
        if Array.is(value) then
            local old = record[key]
            if not Array.is(old) then
                old = {}
                record[key] = old
                changed = true
            end
            changed = settings(old, value) or changed
        else
            changed = scalar(record, key, value) or changed
        end
    end
    for key in pairs(record) do
        if not source or source[key] == nil then
            record[key] = nil
            changed = true
        end
    end
    return changed
end
return { empty = empty, scalar = scalar, vector = vector, fields = fields, settings = settings }
