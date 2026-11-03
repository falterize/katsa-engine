local Tables = require('../../core.tables')
local Array = require('../../math.array')
local ipairs = require('../../math.array').ipairs
local pairs = require('../../math.array').pairs
-- Definitions are reusable game modules; registrations belong to one World3D.
local Node = require('./baseNode')

local Registry = {}

function Registry.register(world, name, definition)
    assert(
        type(name) == 'string' and name ~= '' and Array.is(definition),
        'Registration requires a nonempty name and definition'
    )
    assert(not world.root.destroyed, 'Cannot register types in a released World3D')
    assert(
        not Node.classes[name] and not Node.aliases[name],
        'Custom types cannot replace global classes: ' .. name
    )
    local properties = definition.properties or {}
    assert(Array.is(properties), 'Type properties must be descriptors')
    for key, descriptor in pairs(properties) do
        assert(
            type(key) == 'string' and key:sub(1, 1) ~= '_' and Array.is(descriptor),
            'Custom properties require public names and descriptor tables'
        )
    end
    for _, hook in ipairs({ 'initialize', 'start', 'update' }) do
        assert(
            definition[hook] == nil or type(definition[hook]) == 'function',
            'Custom ' .. hook .. ' hook must be a function'
        )
    end
    local base = definition.base or 'Node3D'
    if type(base) == 'string' then
        base = Node.getClass(base, world)
    end
    assert(
        not base.registrationWorld or base.registrationWorld == world,
        'Custom base class must belong to the same World3D'
    )
    -- Validate before inserting anything: failed registration does not reserve a name.
    world.nodeTypes = world.nodeTypes or {}
    local class = Node.define(name, base, world.nodeTypes)
    class.propertySchema = Tables.copyAuthored(properties)
    class.scriptUpdate = definition.update or base.scriptUpdate
    for key, value in pairs(definition) do
        if key ~= 'base' and key ~= 'properties' and (key ~= 'update' or not base.update) then
            class[key] = value
        end
    end
    local initialize = definition.initialize
    class.initialize = function(node)
        node.enabled, node.visible = node.enabled ~= false, node.visible ~= false
        for key, descriptor in pairs(class.propertySchema) do
            if node[key] == nil and descriptor.default ~= nil then
                node[key] = Tables.copyAuthored(descriptor.default)
            end
        end
        if initialize then
            initialize(node)
        end
    end
    class.registrationWorld = world
    return class
end

return Registry
