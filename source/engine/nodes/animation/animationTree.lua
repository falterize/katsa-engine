-- AnimationTree node: blend graphs and state machines for the Animator of a model.
--
--   world:create('AnimationTree', {
--       animator = model.animator,            -- or place the node under the model instance
--       definition = { type = 'Blend1D', param = 'speed', points = { { 0, 'Idle' }, { 1, 'Walk' } } },
--   }, modelRoot)
--   tree:set('speed', 0.5)                    -- parameters; tree:trigger('jump'); tree:travel('Air')
--
-- `definition` is a graph table (see engine/animation/tree); `definitionFile` names a Lua file
-- that returns one. The inspector shows `active`, the Animator it drives and the current state.
local Node = require('../core.baseNode')
local Tree = require('../../animation.tree')

local Class = Node.define('AnimationTree', 'Node')
Class.propertySchema = {
    active = { hint = 'Drives the Animator when on. Turn off to freeze the blend weights.' },
    animator = {
        kind = 'node',
        nodeClass = 'Animator',
        hint = 'The Animator of the model to drive. Empty uses the model this node sits under.',
    },
    definitionFile = {
        hint = 'Project path of a Lua file that returns the graph. Used when no definition table '
            .. 'was given.',
    },
    state = {
        readOnly = true,
        get = function(node)
            return node.tree and node.tree:state() or ''
        end,
        hint = 'Active state of the root state machine.',
    },
}

function Class.initialize(self)
    self.active = self.active ~= false
end

local function animatorOf(node)
    if node.animator then
        return node.animator
    end
    local parent = node.parent
    while parent do
        local animator = parent.model and parent.model.animator
        if animator then
            return animator
        end
        parent = parent.parent
    end
end

function Class.mount(world, properties, parent)
    local node = Node.new('AnimationTree', properties, parent)
    node._world = world
    node:setProcess(true)
    return node
end

-- Builds the tree as soon as an Animator is reachable (the model may appear after this node).
function Class:connect()
    if self.tree then
        return true
    end
    local animator = animatorOf(self)
    if not animator or animator.destroyed then
        return false
    end
    local definition = self.definition
    if not definition and self.definitionFile and self.definitionFile ~= '' then
        local chunk = assert(
            loadstring(assert(katsa.filesystem.read(self.definitionFile)), self.definitionFile)
        )
        definition = chunk()
    end
    assert(definition, 'AnimationTree needs a definition or a definitionFile')
    self.animator = animator
    self.tree = Tree.new(animator, definition)
    self.tree.active = self.active
    for name, value in pairs(self._pending or {}) do
        self.tree:set(name, value)
    end
    self.tree.onStateChanged = function(machine, from, to)
        self:emit('StateChanged', machine.name, from, to)
    end
    self:onDestroy(function()
        if self.tree then
            self.tree:destroy()
            self.tree = nil
        end
    end)
    return true
end

function Class:update()
    if self:connect() then
        self.tree.active = self.active
    end
end

-- Parameter and travel calls work once the tree is connected (the first update after the model
-- exists); before that they are remembered.
function Class:set(name, value)
    self._pending = self._pending or {}
    self._pending[name] = value
    if self:connect() then
        self.tree:set(name, value)
    end
end

function Class:get(name)
    return self.tree and self.tree:get(name) or (self._pending and self._pending[name])
end

function Class:trigger(name)
    if self:connect() then
        self.tree:trigger(name)
    end
end

function Class:travel(state, machine, fade)
    assert(self:connect(), 'AnimationTree has no Animator yet')
    self.tree:travel(state, machine, fade)
end

return Class
