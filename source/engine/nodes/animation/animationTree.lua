-- AnimationTree node: blend graphs and state machines for the Animator of a model.
--
--   world:create('AnimationTree', {
--       animator = model.animator,            -- or place the node under the model instance
--       definition = { type = 'Blend1D', param = 'speed', points = { { 0, 'Idle' }, { 1, 'Walk' } } },
--   }, modelRoot)
--   tree:set('speed', 0.5)                    -- parameters; tree:trigger('jump'); tree:travel('Air')
--
-- `definition` is a graph table (see engine/animation/tree); `definitionFile` names a Lua file
-- that returns one. Without either, the graph is read from the AnimationGraphNode children of
-- this node (the first one is the root), so it can be built and edited as nodes in the
-- Workspace; `rebuild()` reads them again after an edit. The inspector shows `active`, the
-- Animator it drives and the current state.
local Node = require('../core.baseNode')
local Tree = require('../../animation.tree')
local FromNodes = require('../../animation.tree.fromNodes')

local Class = Node.define('AnimationTree', 'Node')
Class.propertySchema = {
    active = {},
    liveEdit = {},
    animator = {
        kind = 'node',
        nodeClass = 'Animator',
    },
    definitionFile = {},
    state = {
        readOnly = true,
        get = function(node)
            return node.tree and node.tree:state() or ''
        end,
    },
}

function Class.initialize(self)
    self.active = self.active ~= false
    self.liveEdit = self.liveEdit ~= false
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
    self._fromNodes = false
    if not definition then
        local root = FromNodes.root(self)
        definition = root and FromNodes.build(root)
        self._fromNodes = root ~= nil
        self._signature = root and FromNodes.signature(root)
    end
    assert(
        definition,
        'AnimationTree needs a definition, a definitionFile or an AnimationGraphNode child'
    )
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

-- Reads the graph again (after the nodes below were edited). Parameters keep their values.
function Class:rebuild()
    local params = self.tree and self.tree.params
    if self.tree then
        self.tree:destroy()
        self.tree = nil
    end
    if self:connect() and params then
        for name, value in pairs(params) do
            self.tree:set(name, value)
        end
    end
end

-- Graphs built from nodes are checked for edits a few times a second (`liveEdit`).
local WATCH_INTERVAL = 0.25

function Class:update(dt)
    if not self:connect() then
        return
    end
    self.tree.active = self.active
    if self.liveEdit and self._fromNodes then
        self._watch = (self._watch or 0) + (dt or 0)
        if self._watch >= WATCH_INTERVAL then
            self._watch = 0
            local root = FromNodes.root(self)
            if root and FromNodes.signature(root) ~= self._signature then
                self:rebuild()
            end
        end
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
