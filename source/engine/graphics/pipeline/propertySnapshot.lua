local readValue = require('source.engine.math.managedValue').read
local Array = require('source.engine.math.array')
local ipairs = require('source.engine.math.array').ipairs
-- Per-frame class defaults avoid resolving the same inherited fields for every mesh.
-- Public mutable arrays still compare every component on every inspection.
local Snapshot = require('source.engine.core.valueSnapshot')
local Types = require('source.engine.math.valueTypes')

local empty = {}

local function vector(record, key, value)
    value = readValue(value)
    local old = record[key]
    if Array.is(old) then
        local count = #value
        if count == #old then
            if count == 3 then
                local x, y, z = value[1], value[2], value[3]
                if old[1] == x and old[2] == y and old[3] == z then
                    return false
                end
                old[1], old[2], old[3] = x, y, z
                return true
            elseif count == 2 then
                local x, y = value[1], value[2]
                if old[1] == x and old[2] == y then
                    return false
                end
                old[1], old[2] = x, y
                return true
            elseif count == 4 then
                local x, y, z, w = value[1], value[2], value[3], value[4]
                if old[1] == x and old[2] == y and old[3] == z and old[4] == w then
                    return false
                end
                old[1], old[2], old[3], old[4] = x, y, z, w
                return true
            end
        end
    end
    return Snapshot.vector(record, key, value)
end

local function compile(keys, vectors, node)
    local reuse = {}
    local code = {
        'local rawget,type,vector=rawget,type,vector;',
        'return function(r,n,d,t,s,skip) local changed=false; local v;',
    }

    local function read(key)
        local k = string.format('%q', key)
        if key == 'parent' then
            return "v=rawget(n,'parent');if v==nil then v=rawget(n,'_parent') end;"
        end
        if key == 'enabled' and node._class.getEnabled then
            return 'v=n.enabled;'
        end
        local observed = rawget(node, '_observedFields')
        if observed and observed[key] then
            return 'v=s[' .. k .. '];if v==nil then v=d[' .. k .. '] end;'
        end
        if Types.kind(node, key) then
            return 'v=t[' .. k .. '];if v==nil then v=d[' .. k .. '] end;'
        end
        -- Established raw fields use a VM table read. If removed, Node.__index
        -- still resolves the current class default instead of leaving stale data.
        if rawget(node, key) ~= nil then
            return 'v=n[' .. k .. '];'
        end
        return 'v=rawget(n,' .. k .. '); if v==nil then v=d[' .. k .. '] end;'
    end
    local tracked, untracked = {}, {}
    local fields = rawget(node, '_observedFields')
    for _, key in ipairs(keys) do
        local target = fields
                and fields[key]
                and not (key == 'enabled' and node._class.getEnabled)
                and tracked
            or untracked
        target[#target + 1] = key
    end

    local function append(list)
        for _, key in ipairs(list) do
            local k = string.format('%q', key)
            code[#code + 1] = read(key)
                .. 'if r['
                .. k
                .. ']~=v then r['
                .. k
                .. ']=v;changed=true end;'
        end
    end
    code[#code + 1] = 'if not skip then'
    append(tracked)
    code[#code + 1] = 'end;'
    append(untracked)
    local managed, mutable = {}, {}
    for _, key in ipairs(vectors) do
        local list = Types.kind(node, key) and managed or mutable
        list[#list + 1] = key
    end

    local function appendVectors(list)
        for _, key in ipairs(list) do
            local k = string.format('%q', key)
            code[#code + 1] = read(key)
                .. 'if Array.is(v) then changed=vector(r,'
                .. k
                .. ',v) or changed '
                .. 'elseif r['
                .. k
                .. ']~=v then r['
                .. k
                .. ']=v;changed=true end;'
        end
    end
    code[#code + 1] = 'if not skip then'
    appendVectors(managed)
    code[#code + 1] = 'end;'
    appendVectors(mutable)
    code[#code + 1] = 'return changed end'
    local chunk = assert(loadstring(table.concat(code, '\n'), 'render.propertySnapshot'))
    setfenv(chunk, { rawget = rawget, vector = vector, type = type, Array = Array })
    -- Only privately written scalars and optional mutable matrices still need reads.
    for _, key in ipairs(untracked) do
        local k = string.format('%q', key)
        reuse[#reuse + 1] = read(key) .. 'if r[' .. k .. ']~=v then return false end;'
    end
    for _, key in ipairs(mutable) do
        local k = string.format('%q', key)
        reuse[#reuse + 1] = 'if r[' .. k .. ']~=nil then return false end;'
    end
    local reuseChunk = assert(
        loadstring(
            'return function(r,n,d,t,s) local v;' .. table.concat(reuse, '\n') .. 'return true end',
            'render.propertyReuse'
        )
    )
    setfenv(reuseChunk, { rawget = rawget })
    return chunk(), reuseChunk()
end
local compiled = {}

local function checker(class, keys, vectors, node)
    local group = compiled[class]
    if not group then
        group = {}
        compiled[class] = group
    end
    local variants = group[keys]
    if not variants then
        variants = {}
        group[keys] = variants
    end
    local cached = variants[vectors]
    if not cached or cached.getEnabled ~= class.getEnabled then
        local check, reuse = compile(keys, vectors, node)
        cached = { getEnabled = class.getEnabled, check = check, reuse = reuse }
        variants[vectors] = cached
    end
    return cached.check, cached.reuse
end
-- Keep only field shape, never a live node/hierarchy, in a compiled schema.
local function shape(node, keys, vectors)
    local sample =
        { _class = node._class, _observedFields = rawget(node, '_observedFields'), isA = node.isA }
    for _, list in ipairs({ keys, vectors }) do
        for _, key in ipairs(list) do
            if rawget(node, key) ~= nil then
                sample[key] = true
            end
        end
    end
    return sample
end
local Properties = {}

local function refresh(state, context)
    local class, keys, vectors = state.class, state.keys, state.vectors
    local values = state.values
    if values.epoch ~= context.epoch then
        local defaultsChanged = values.revision == nil
        if state.getEnabled ~= class.getEnabled then
            state.getEnabled = class.getEnabled
            state.check, state.reuse = checker(class, keys, vectors, state.sample)
            defaultsChanged = true
        end
        for _, key in ipairs(keys) do
            local value = class[key]
            if values[key] ~= value then
                values[key] = value
                defaultsChanged = true
            end
        end
        state.vectorDefaults = state.vectorDefaults or {}
        for _, key in ipairs(vectors) do
            local value = class[key]
            defaultsChanged = Snapshot.vector(state.vectorDefaults, key, value) or defaultsChanged
            values[key] = value
        end
        if defaultsChanged then
            values.revision = (values.revision or 0) + 1
        end
        values.epoch = context.epoch
    end
end

function Properties.begin(context)
    for _, state in ipairs(context.propertySchemas or empty) do
        refresh(state, context)
    end
end

function Properties.unchanged(record, node, context)
    local state = record._propertySchema
    if
        not state
        or state.class ~= rawget(node, '_class')
        or state.getEnabled
        or record._scalarRevision ~= rawget(node, '_propertyRevision')
        or record._scalarDefaults ~= state.values.revision
    then
        return false
    end
    return state.reuse(record, node, state.values, empty, rawget(node, '_observedValues') or empty)
end

function Properties.fast(record, node, keys, vectors, context)
    local state = record._propertySchema
    if
        not state
        or state.keys ~= keys
        or state.vectors ~= vectors
        or state.class ~= node._class
        or record._scalarSchema ~= state
        or record._scalarRevision == nil
        or record._scalarRevision ~= node._propertyRevision
        or record._scalarDefaults ~= state.values.revision
    then
        return false
    end
    context.scalarNodesSkipped = (context.scalarNodesSkipped or 0) + 1
    return true,
        state.check(
            record,
            node,
            state.values,
            empty,
            rawget(node, '_observedValues') or empty,
            true
        )
end

function Properties.fields(record, node, keys, vectors, context)
    local class = rawget(node, '_class')
    if not class or rawget(node, '_billboardVectors') then
        return Snapshot.fields(record, node, keys, vectors)
    end
    vectors = vectors or empty
    local state = record._propertySchema
    if not state or state.class ~= class or state.keys ~= keys or state.vectors ~= vectors then
        local defaults = context.defaults
        if not defaults then
            defaults = {}
            context.defaults = defaults
        end
        local current = defaults[class]
        if not current then
            current = {}
            defaults[class] = current
        end
        local group = current[keys]
        if not group then
            group = {}
            current[keys] = group
        end
        state = group[vectors]
        if not state then
            state = {
                class = class,
                keys = keys,
                vectors = vectors,
                values = {},
                getEnabled = class.getEnabled,
                sample = shape(node, keys, vectors),
            }
            state.check, state.reuse = checker(class, keys, vectors, node)
            group[vectors] = state
            context.propertySchemas = context.propertySchemas or {}
            context.propertySchemas[#context.propertySchemas + 1] = state
        end
        record._propertySchema = state
    end
    refresh(state, context)
    local values = state.values
    local revision = rawget(node, '_propertyRevision')
    local skip = revision ~= nil
        and record._scalarSchema == state
        and record._scalarRevision == revision
        and record._scalarDefaults == values.revision
    if skip then
        context.scalarNodesSkipped = (context.scalarNodesSkipped or 0) + 1
    else
        context.scalarNodesChecked = (context.scalarNodesChecked or 0) + 1
    end
    local changed = state.check(
        record,
        node,
        values,
        rawget(node, '_typedValues') or empty,
        rawget(node, '_observedValues') or empty,
        skip
    )
    record._scalarSchema, record._scalarRevision, record._scalarDefaults =
        state, revision, values.revision
    return changed
end

return Properties
