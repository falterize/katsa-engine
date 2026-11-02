local Node = require('../../core.baseNode')
local Joints = require('source.engine.physics.2d.joints')

local Constraint2D = Node.define('Constraint2D', 'Node')
Constraint2D.kind = 'Hinge'
Constraint2D.propertySchema = {
    attachment0 = { kind = 'node', nodeClass = 'Attachment2D' },
    attachment1 = { kind = 'node', nodeClass = 'Attachment2D' },
    status = { readOnly = true },
    enabled = {},
    limitsEnabled = {},
    lowerLimit = {},
    upperLimit = {},
    motorEnabled = {},
    motorSpeed = {},
    motorForce = { min = 0 },
    length = { min = 0 },
    maxLength = { min = 0 },
    frequency = { min = 0 },
    dampingRatio = { min = 0, max = 1 },
    allowCollision = {},
    breakForce = { min = 0 },
    breakTorque = { min = 0 },
    maxForce = { min = 0 },
    maxTorque = { min = 0 },
    ratio = {},
    linearOffset = { kind = 'vector' },
    angularOffset = {},
    correctionFactor = { min = 0, max = 1 },
    joint0 = { kind = 'node', nodeClass = 'Constraint2D' },
    joint1 = { kind = 'node', nodeClass = 'Constraint2D' },
    groundAnchor0 = { kind = 'vector' },
    groundAnchor1 = { kind = 'vector' },
    target = { kind = 'vector' },
}

function Constraint2D.initialize(self)
    self.enabled = self.enabled ~= false
    self.lowerLimit, self.upperLimit = self.lowerLimit or -45, self.upperLimit or 45
    self.motorSpeed, self.motorForce = self.motorSpeed or 0, self.motorForce or 0
    self.frequency, self.dampingRatio =
        self.frequency or (self.kind == 'Weld' and 0 or 4), self.dampingRatio or 0.7
    self.breakForce, self.breakTorque = self.breakForce or 0, self.breakTorque or 0
    self.maxForce, self.maxTorque = self.maxForce or 10000, self.maxTorque or 10000
    self.ratio = self.ratio or 1
    self.status = 'Waiting for attachments'
end

function Constraint2D.mount(context, properties, parent)
    parent = parent or context
    local owner = parent
    while owner and not owner:isA('World2D') do
        owner = owner.parent
    end
    assert(owner and owner.physics2D, 'Constraint2D requires a physical World2D')
    local node = Node.new(properties.className or 'Constraint2D', properties, parent)
    node._plane = owner
    node.physics = owner.physics2D
    node.physics.constraints[#node.physics.constraints + 1] = node
    node:onDestroy(function()
        node:releaseJoint()
        for i, item in ipairs(node.physics.constraints) do
            if item == node then
                table.remove(node.physics.constraints, i)
                break
            end
        end
    end)
    return node
end

function Constraint2D:releaseJoint()
    for _, other in ipairs(self.physics.constraints) do
        if other ~= self and (other.joint0 == self or other.joint1 == self) and other.joint then
            other:releaseJoint()
        end
    end
    if self.joint and not self.joint:isDestroyed() then
        self.joint:destroy()
    end
    self.joint, self._jointInputs = nil, nil
end

Constraint2D.step = Joints.step
Constraint2D.checkBreak = Joints.checkBreak

function Constraint2D:repair()
    self.broken = false
    self:releaseJoint()
end

require('./constraintTypes').register(Constraint2D)

return Constraint2D
