-- AnimationGraphNode: one node of an AnimationTree graph, as a node you can see and edit in the
-- Workspace. Put the root graph node under an `AnimationTree`, its inputs under it:
--
--   local tree = world:create('AnimationTree', {}, modelRoot)
--   local mix = world:create('AnimationGraphNode', { type = 'Blend1D', param = 'speed' }, tree)
--   world:create('AnimationGraphNode', { type = 'Animation', clip = 'Idle', pointX = 0 }, mix)
--   world:create('AnimationGraphNode', { type = 'Animation', clip = 'Walk', pointX = 1 }, mix)
--
-- `type` picks the node kind (the same kinds as a graph table, see engine/animation/tree); the
-- inspector shows only the properties of that kind. The child order gives the roles of the
-- inputs (Blend: a, b; Add2: base, add; OneShot: input, shot ...). Transition inputs and
-- StateMachine states are named by their node `name`; StateMachine transitions are
-- AnimationTransition children. The tree reads the nodes when it connects (`AnimationTree:rebuild`
-- reads them again).
local Node = require('../core.baseNode')

local Class = Node.define('AnimationGraphNode', 'Node')

local KINDS = {
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
local CURVES = { 'Default', 'linear', 'smooth', 'easeIn', 'easeOut' }

local function only(...)
    return { key = 'type', oneOf = { ... } }
end

local function treeOf(node)
    local parent = node.parent
    while parent do
        if parent.isA and parent:isA('AnimationTree') then
            return parent
        end
        parent = parent.parent
    end
end

-- Clip names of the model the tree drives, when it is known.
local function clipNames(node)
    local tree = treeOf(node)
    local animator = tree and tree.animator
    local model = animator and animator.model
    local list = {}
    for _, clip in ipairs(model and model.animations or {}) do
        list[#list + 1] = clip.name
    end
    return list
end

local function stateNames(node)
    local list = {}
    for _, child in ipairs(node.children) do
        if child.isA and child:isA('AnimationGraphNode') then
            list[#list + 1] = child.name
        end
    end
    return list
end

local function parentIs(...)
    local kinds = { ... }
    return function(node)
        local parent = node.parent
        if not (parent and parent.isA and parent:isA('AnimationGraphNode')) then
            return false
        end
        for _, kind in ipairs(kinds) do
            if parent.type == kind then
                return true
            end
        end
        return false
    end
end

Class.propertySchema = {
    type = { options = KINDS },
    clip = { options = clipNames, visibleWhen = only('Animation') },
    speed = { min = 0, visibleWhen = only('Animation') },
    stretch = { min = 0, visibleWhen = only('Animation') },
    playMode = { options = { 'Forward', 'Backward' }, visibleWhen = only('Animation') },
    loopMode = { options = { 'None', 'Linear', 'PingPong' }, visibleWhen = only('Animation') },
    startTime = { min = 0, visibleWhen = only('Animation') },
    endTime = { min = 0, visibleWhen = only('Animation') },
    order = { visibleWhen = only('Animation') },
    param = {
        visibleWhen = only(
            'Blend',
            'Blend1D',
            'Blend2D',
            'Blend3',
            'Add2',
            'Add3',
            'Sub2',
            'TimeScale',
            'TimeSeek',
            'Transition'
        ),
    },
    paramY = { visibleWhen = only('Blend2D') },
    value = { visibleWhen = only('Blend', 'Blend3', 'Add2', 'Add3', 'Sub2', 'TimeScale') },
    blendMode = { options = { 'Interpolated', 'Discrete', 'Carry' }, visibleWhen = only('Blend1D', 'Blend2D') },
    sync = { visibleWhen = only('Blend', 'Blend1D', 'Blend2D', 'Blend3', 'Add2', 'Add3', 'Sub2', 'OneShot', 'Transition') },
    filter = { visibleWhen = only('Blend', 'Add2', 'Add3', 'Sub2', 'OneShot') },
    filterChildren = { visibleWhen = only('Blend', 'Add2', 'Add3', 'Sub2', 'OneShot') },
    reference = { options = { 'firstFrame', 'rest' }, visibleWhen = only('Add2', 'Add3', 'Sub2', 'OneShot') },
    request = { visibleWhen = only('OneShot') },
    abort = { visibleWhen = only('OneShot') },
    fadeIn = { min = 0, visibleWhen = only('OneShot') },
    fadeOut = { min = 0, visibleWhen = only('OneShot') },
    restartOnRequest = { visibleWhen = only('OneShot') },
    shotMode = { options = { 'Blend', 'Add' }, visibleWhen = only('OneShot') },
    fade = { min = 0, visibleWhen = only('Transition', 'StateMachine') },
    curve = { options = CURVES, visibleWhen = only('Transition', 'StateMachine') },
    reset = { visibleWhen = only('Transition') },
    startState = { options = stateNames, visibleWhen = only('StateMachine') },
    pointX = { visibleWhen = parentIs('Blend1D', 'Blend2D') },
    pointY = { visibleWhen = parentIs('Blend2D') },
}

function Class.initialize(self)
    self.type = self.type or 'Animation'
    self.clip = self.clip or ''
    self.speed = self.speed or 1
    self.stretch = self.stretch or 1
    self.playMode = self.playMode or 'Forward'
    self.loopMode = self.loopMode or 'Linear'
    self.startTime = self.startTime or 0
    self.endTime = self.endTime or 0
    self.order = self.order or 0
    self.param = self.param or ''
    self.paramY = self.paramY or ''
    self.value = self.value or (self.type == 'TimeScale' and 1 or 0)
    self.blendMode = self.blendMode or 'Interpolated'
    self.sync = self.sync == true
    self.filter = self.filter or ''
    self.filterChildren = self.filterChildren == true
    self.reference = self.reference or 'firstFrame'
    self.request = self.request or ''
    self.abort = self.abort or ''
    self.fadeIn = self.fadeIn or 0.1
    self.fadeOut = self.fadeOut or 0.1
    self.restartOnRequest = self.restartOnRequest == true
    self.shotMode = self.shotMode or 'Blend'
    self.fade = self.fade or 0.2
    self.curve = self.curve or 'Default'
    self.reset = self.reset ~= false
    self.startState = self.startState or ''
    self.pointX = self.pointX or 0
    self.pointY = self.pointY or 0
end

return Class
