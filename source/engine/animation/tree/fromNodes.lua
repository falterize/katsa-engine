-- Builds a graph definition (the table `AnimationTree.new` takes) from AnimationGraphNode and
-- AnimationTransition nodes, so a graph can be authored and edited as nodes in the Workspace.
-- Inputs are the child nodes in order (their roles depend on the parent's `type`):
--   Blend a, b | Blend3 a, b, c | Add2 base, add | Sub2 base, sub | Add3 base, minus, plus
--   OneShot input, shot | TimeScale, TimeSeek child | Blend1D/Blend2D points (child pointX/pointY)
--   Transition inputs (child names) | StateMachine states (child names) + AnimationTransition children
local FromNodes = {}

local ROLES = {
    Blend = { 'a', 'b' },
    Blend3 = { 'a', 'b', 'c' },
    Add2 = { 'base', 'add' },
    Sub2 = { 'base', 'sub' },
    Add3 = { 'base', 'minus', 'plus' },
    OneShot = { 'input', 'shot' },
    TimeScale = { 'child' },
    TimeSeek = { 'child' },
}

local function isGraphNode(node)
    return node.isA and node:isA('AnimationGraphNode')
end

local function graphChildren(node)
    local list = {}
    for _, child in ipairs(node.children) do
        if isGraphNode(child) then
            list[#list + 1] = child
        end
    end
    return list
end

-- 'Spine_001, Upper_Arm_R' -> { 'Spine_001', 'Upper_Arm_R' }; empty text -> nil.
local function names(text)
    if type(text) ~= 'string' or text:match('^%s*$') then
        return nil
    end
    local list = {}
    for name in text:gmatch('[^,]+') do
        list[#list + 1] = name:match('^%s*(.-)%s*$')
    end
    return list
end

-- A number, or the name of a parameter when `param` is set.
local function value(node, key)
    return node.param ~= '' and node.param or node[key or 'value']
end

local build

local function common(node, definition)
    definition.name = node.name
    definition.sync = node.sync
    local filter = names(node.filter)
    if filter then
        definition.filter = filter
        definition.filterChildren = node.filterChildren
    end
    if node.reference ~= 'firstFrame' then
        definition.reference = node.reference
    end
    return definition
end

local function stateMachine(node)
    local states, transitions = {}, {}
    for _, child in ipairs(node.children) do
        if isGraphNode(child) then
            assert(child.name ~= '', 'A state of a StateMachine node needs a name')
            states[child.name] = build(child)
        elseif child.isA and child:isA('AnimationTransition') then
            local transition = {
                from = child.from,
                to = child.to,
                when = child.param ~= '' and child.param or nil,
                expression = child.expression ~= '' and child.expression or nil,
                onFinish = child.onFinish or nil,
                switch = child.switch,
                advance = child.advance,
                priority = child.priority,
                fade = child.fade >= 0 and child.fade or nil,
                curve = child.curve ~= 'Default' and child.curve or nil,
                reset = child.reset,
            }
            transitions[#transitions + 1] = transition
        end
    end
    return common(node, {
        type = 'StateMachine',
        start = node.startState ~= '' and node.startState or nil,
        fade = node.fade,
        curve = node.curve ~= 'Default' and node.curve or nil,
        states = states,
        transitions = transitions,
    })
end

function build(node)
    local kind = node.type
    if kind == 'Animation' then
        assert(node.clip ~= '', 'Animation node ' .. node.name .. ' needs a clip')
        return common(node, {
            clip = node.clip,
            speed = node.speed,
            loopMode = node.loopMode,
            playMode = node.playMode,
            startTime = node.startTime > 0 and node.startTime or nil,
            endTime = node.endTime > 0 and node.endTime or nil,
            stretch = node.stretch,
            order = node.order,
        })
    elseif kind == 'StateMachine' then
        return stateMachine(node)
    end
    local children = graphChildren(node)
    local definition = common(node, { type = kind })
    local roles = ROLES[kind]
    if roles then
        assert(#children >= #roles, ('%s node %s needs %d input nodes'):format(kind, node.name, #roles))
        for i, role in ipairs(roles) do
            definition[role] = build(children[i])
        end
    elseif kind == 'Transition' or kind == 'Blend1D' or kind == 'Blend2D' then
        assert(#children >= 1, kind .. ' node ' .. node.name .. ' needs input nodes')
    end
    if kind == 'Blend' or kind == 'Blend3' or kind == 'Add2' or kind == 'Sub2' or kind == 'Add3' then
        definition.amount = value(node)
    elseif kind == 'OneShot' then
        definition.request = node.request
        definition.abort = node.abort ~= '' and node.abort or nil
        definition.fadeIn, definition.fadeOut = node.fadeIn, node.fadeOut
        definition.restart = node.restartOnRequest
        definition.mode = node.shotMode
    elseif kind == 'TimeScale' then
        definition.scale = value(node, 'value')
    elseif kind == 'TimeSeek' then
        definition.seek = node.param
    elseif kind == 'Transition' then
        definition.param = node.param
        definition.fade = node.fade
        definition.curve = node.curve ~= 'Default' and node.curve or nil
        definition.reset = node.reset
        definition.inputs = {}
        for _, child in ipairs(children) do
            definition.inputs[#definition.inputs + 1] = { child.name, build(child) }
        end
    elseif kind == 'Blend1D' then
        definition.param = node.param
        definition.mode = node.blendMode
        definition.points = {}
        for _, child in ipairs(children) do
            definition.points[#definition.points + 1] = { child.pointX, build(child) }
        end
    elseif kind == 'Blend2D' then
        definition.x, definition.y = node.param, node.paramY
        definition.mode = node.blendMode
        definition.points = {}
        for _, child in ipairs(children) do
            definition.points[#definition.points + 1] = { child.pointX, child.pointY, build(child) }
        end
    end
    return definition
end

-- The definition of the graph below `node` (an AnimationGraphNode).
function FromNodes.build(node)
    assert(isGraphNode(node), 'FromNodes.build needs an AnimationGraphNode')
    return build(node)
end

-- The first AnimationGraphNode child of `parent` (the root of its graph), or nil.
function FromNodes.root(parent)
    for _, child in ipairs(parent.children) do
        if isGraphNode(child) then
            return child
        end
    end
end

-- Text that changes when any property or child of the graph below `node` changes; the tree
-- compares it to notice edits made in the Workspace.
local keyLists = setmetatable({}, { __mode = 'k' })

local function keysOf(node)
    local class = node._class
    local keys = keyLists[class]
    if not keys then
        keys = {}
        for key in pairs(class.propertySchema) do
            keys[#keys + 1] = key
        end
        table.sort(keys)
        keyLists[class] = keys
    end
    return keys
end

function FromNodes.signature(node)
    local parts = {}
    local function walk(current)
        parts[#parts + 1] = current.name
        for _, key in ipairs(keysOf(current)) do
            parts[#parts + 1] = tostring(current[key])
        end
        for _, child in ipairs(current.children) do
            if child.isA and (child:isA('AnimationGraphNode') or child:isA('AnimationTransition')) then
                walk(child)
            end
        end
        parts[#parts + 1] = ')'
    end
    walk(node)
    return table.concat(parts, '|')
end

return FromNodes
