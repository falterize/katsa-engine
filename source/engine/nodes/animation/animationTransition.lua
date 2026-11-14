-- AnimationTransition: a transition of an AnimationGraphNode of type StateMachine (put it under
-- that node). `from` and `to` name states (child graph nodes); `from = '*'` means any state, and
-- `to = 'End'` ends the machine. The condition is a parameter name (`param`), an `expression` such
-- as 'speed > 0.5 and not grounded', or `onFinish`.
local Node = require('../core.baseNode')

local Class = Node.define('AnimationTransition', 'Node')

local function states(node)
    local list = { '*' }
    local parent = node.parent
    for _, child in ipairs(parent and parent.children or {}) do
        if child.isA and child:isA('AnimationGraphNode') then
            list[#list + 1] = child.name
        end
    end
    return list
end

local function targets(node)
    local list = states(node)
    table.remove(list, 1)
    list[#list + 1] = 'End'
    return list
end

Class.propertySchema = {
    from = { options = states },
    to = { options = targets },
    param = {},
    expression = {},
    onFinish = {},
    switch = { options = { 'Immediate', 'Sync', 'AtEnd' } },
    advance = { options = { 'Auto', 'Disabled' } },
    priority = {},
    fade = { min = -1 },
    curve = { options = { 'Default', 'linear', 'smooth', 'easeIn', 'easeOut' } },
    reset = {},
}

function Class.initialize(self)
    self.from = self.from or '*'
    self.to = self.to or ''
    self.param = self.param or ''
    self.expression = self.expression or ''
    self.onFinish = self.onFinish == true
    self.switch = self.switch or 'Immediate'
    self.advance = self.advance or 'Auto'
    self.priority = self.priority or 0
    self.fade = self.fade or -1
    self.curve = self.curve or 'Default'
    self.reset = self.reset ~= false
end

return Class
