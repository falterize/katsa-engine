local ipairs = require('../../math.array').ipairs
local pairs = require('../../math.array').pairs
local Array = require('../../math.array')
local Managed = require('../../math.managedValue')

-- Node:clone(properties, parent): a deep copy of the node and its descendants, like Roblox's
-- Instance:Clone(). The copy is built from the same public property list the Workspace
-- inspector edits, so it never copies runtime caches, native handles or signal connections.
local Clone = {}

-- Runtime/identity keys that must not travel to a copy.
local SKIPPED = { parent = true, className = true, children = true, destroyed = true }

-- Copies plain tables deeply; node references, resources and functions are shared.
local function copyValue(value, seen)
    if type(value) ~= 'table' then
        return value
    end
    if Managed.is(value) then
        return Managed.toArray(value)
    end
    if rawget(value, '_node') or getmetatable(value) then
        return value
    end
    seen = seen or {}
    if seen[value] then
        return seen[value]
    end
    local result = {}
    seen[value] = result
    for key, item in pairs(value) do
        result[key] = copyValue(item, seen)
    end
    return result
end

function Clone.collect(node)
    local Schema = require('../../editor.inspectors.schema')
    local fields = require('../../editor.inspectors.propertyPolicy').fields
    local result = { name = node.name }
    for _, key in ipairs(Schema.keys(node, fields)) do
        if not SKIPPED[key] then
            local value = node[key]
            if value ~= nil and type(value) ~= 'function' then
                result[key] = copyValue(value)
            end
        end
    end
    return result
end

-- Worlds register meshes and other named objects by unique name, so a copy of 'Wheel' becomes
-- 'Wheel_2' (then 'Wheel_3'...) while the original is alive. Unregistered names stay unchanged.
local function uniqueName(world, name)
    local registry = world and world.byName
    if not registry or not name or not registry[name] then
        return name
    end
    local base = name:gsub('_%d+$', '')
    local index = 2
    while registry[base .. '_' .. index] do
        index = index + 1
    end
    return base .. '_' .. index
end

local function build(node, overrides, parent)
    local properties = Clone.collect(node)
    properties.name = uniqueName(node._sceneWorld, properties.name)
    for key, value in pairs(overrides or {}) do
        -- Roblox-style capitalised names are accepted for the common identity fields.
        if key == 'Name' then
            key = 'name'
        elseif key == 'Parent' then
            key = 'parent'
        end
        if key ~= 'parent' then
            properties[key] = value
        end
    end
    local world = node._sceneWorld
    local copy
    if world and world.create then
        copy = world:create(node.className, properties, parent)
    else
        copy =
            require('./baseNode').create(node.className, properties, parent)
    end
    return copy
end

function Clone.node(node, overrides, parent)
    assert(not node.destroyed, 'Cannot clone a destroyed node')
    overrides = overrides or {}
    if parent == nil then
        parent = overrides.parent or overrides.Parent
    end
    if parent == nil then
        parent = node.parent
    end
    local copy = build(node, overrides, parent)
    for _, child in ipairs(node.children) do
        if not child.destroyed and not child._transientClone then
            -- A class may create required children itself (an Environment inside a World).
            local existing = copy:find(child.name)
            if not (existing and existing.className == child.className) then
                Clone.node(child, nil, copy)
            end
        end
    end
    return copy
end

return Clone
