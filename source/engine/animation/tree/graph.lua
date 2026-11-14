-- Builds graph nodes from plain definition tables. A table with `clip` is an Animation leaf;
-- anything else names its `type`. Already built nodes pass through unchanged.
local Graph = {}

local constructors = {
    Animation = require('./nodes.animation').new,
    Blend = require('./nodes.blend').new,
    Blend3 = require('./nodes.blend3').new,
    Add2 = require('./nodes.add2').new,
    Add3 = require('./nodes.add3').new,
    Sub2 = require('./nodes.sub2').new,
    OneShot = require('./nodes.oneShot').new,
    Transition = require('./nodes.transition').new,
    TimeSeek = require('./nodes.timeSeek').new,
    Blend1D = require('./nodes.blend1D').new,
    Blend2D = require('./nodes.blend2D').new,
    TimeScale = require('./nodes.timeScale').new,
    StateMachine = require('./nodes.stateMachine').new,
}

Graph.types = {
    'Animation',
    'Blend',
    'Blend1D',
    'Blend2D',
    'Blend3',
    'Add2',
    'Add3',
    'Sub2',
    'OneShot',
    'Transition',
    'TimeScale',
    'TimeSeek',
    'StateMachine',
}

function Graph.build(definition)
    if type(definition) == 'string' or type(definition) == 'number' then
        definition = { clip = definition }
    end
    assert(type(definition) == 'table', 'An animation graph node must be a table or a clip name')
    if definition.kind and definition.evaluate then
        return definition
    end
    local kind = definition.type or (definition.clip ~= nil and 'Animation')
    local constructor = assert(constructors[kind], 'Unknown animation graph node: ' .. tostring(kind))
    local node = constructor(definition, Graph.build)
    node.name = node.name or definition.name
    return node
end

return Graph
