-- AnimationGraphNode / AnimationTransition: the tree reads its graph from nodes, shows only the
-- properties of a node's type, offers clip and state names, and rebuilds when a node is edited.
local Schema = require('source.engine.editor.inspectors.schema')
local FromNodes = require('source.engine.animation.tree.fromNodes')

local Module = {}

local function find(node, name)
    if node.name == name then
        return node
    end
    for _, child in ipairs(node.children) do
        local found = find(child, name)
        if found then
            return found
        end
    end
end

local function visible(node, key)
    for _, name in ipairs(Schema.keys(node, {})) do
        if name == key then
            return true
        end
    end
    return false
end

function Module.run(self)
    local window = assert(katsa.window.create(480, 300, { title = 'graphNodes' }))
    local scene = window:runScene('animationTreeLab', { fps = 1000 })
    local lab = scene:getScene().demo
    scene:step(0.05)
    local tree = lab.tree
    self:check(tree.tree ~= nil and tree.tree:state() == 'Ground', 'An AnimationTree builds its graph from AnimationGraphNode children')

    local definition = FromNodes.build(FromNodes.root(tree))
    local machine = definition.input
    self:check(
        definition.type == 'OneShot' and definition.filterChildren and definition.filter[2] == 'Upper_Arm_R',
        'A OneShot node becomes a definition with its bone filter'
    )
    self:check(
        machine.states.Ground.inputs[1][1] == 'Stand' and machine.transitions[1].expression == 'not grounded'
            and machine.transitions[2].switch == 'AtEnd',
        'Named inputs, states and transitions are read from the child nodes'
    )

    local blend = find(tree, 'Walk')
    local clip = find(tree, 'Idle')
    self:check(visible(blend, 'param') and not visible(blend, 'request'), 'The inspector shows only the properties of the node type')
    self:check(visible(clip, 'pointX') and not visible(find(tree, 'Crouch'), 'pointX'), 'Point positions show only under a blend space')
    local clips = Schema.options(clip, 'clip')
    self:check(clips and #clips >= 5, 'The clip property lists the clips of the model')
    self:check(#Schema.options(find(tree, 'Locomotion'), 'startState') == 2, 'startState lists the states of the machine')

    local before = tree.tree
    find(tree, 'Ground').fade = 0.5
    for _ = 1, 8 do
        scene:step(0.05)
    end
    self:check(tree.tree ~= before and tree.tree:state() == 'Ground', 'Editing a graph node rebuilds the tree')
    tree:set('speed', 1)
    scene:step(0.05)
    self:check(tree:get('speed') == 1, 'Parameters survive a rebuild')
    window:close()
end

return Module
