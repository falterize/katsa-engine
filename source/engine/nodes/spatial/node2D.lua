local Node = require('source.engine.nodes.core.baseNode')

local Node2D = Node.define('Node2D', 'Node')
Node2D.propertySchema = {
    position = { kind = 'vector' },
    rotation = {},
    size = { kind = 'vector' },
    scale = { kind = 'vector' },
    visible = {},
    transparency = { min = 0, max = 1 },
}

function Node2D.initialize(self)
    self.position = self.position or { 0, 0 }
    self.rotation = self.rotation or 0
    self.size = self.size or { 32, 32 }
    self.scale = self.scale or { 1, 1 }
    self.visible = self.visible ~= false
    self.enabled = self.enabled ~= false
    self.transparency = self.transparency or 0
end

function Node2D.mount(context, properties, parent)
    parent = parent or context
    local owner = parent
    while owner and not owner:isA('World2D') do
        owner = owner.parent
    end
    assert(owner and not owner.owner, 'Node2D requires a screen World2D ancestor')
    local node = Node.new(properties.className or 'Node2D', properties, parent)
    node._plane = owner
    return node
end

-- Six affine components preserve rotated nonuniform groups, including shear.
-- Native bodies retain rigid poses; the remaining linear transform is baked into fixtures.
function Node2D:getWorldTransform()
    local sx, sy = self.scale[1], self.scale[2]
    assert(
        math.abs(sx) > 0.000001
            and math.abs(sy) > 0.000001
            and math.abs(sx) < math.huge
            and math.abs(sy) < math.huge,
        'Node2D scale must be finite and nonzero'
    )
    local angle = self.rotation
    local c, s = math.cos(math.rad(angle)), math.sin(math.rad(angle))
    local a, b, d, e = c * sx, s * sx, -s * sy, c * sy
    local x, y = self.position[1], self.position[2]
    local parent = self.parent
    while parent and not parent:isA('Node2D') and not parent:isA('World2D') do
        parent = parent.parent
    end
    if parent and parent:isA('Node2D') then
        local pa, pb, pd, pe, px, py, rotation = parent:getWorldTransform()
        return pa * a + pd * b,
            pb * a + pe * b,
            pa * d + pd * e,
            pb * d + pe * e,
            px + pa * x + pd * y,
            py + pb * x + pe * y,
            angle + rotation
    end
    return a, b, d, e, x, y, angle
end

function Node2D:getWorldPose()
    local _, _, _, _, x, y, angle = self:getWorldTransform()
    return x, y, angle
end

function Node2D:setWorldPose(x, y, angle)
    local parent = self.parent
    while parent and not parent:isA('Node2D') and not parent:isA('World2D') do
        parent = parent.parent
    end
    if parent and parent:isA('Node2D') then
        local a, b, c, d, px, py, rotation = parent:getWorldTransform()
        local determinant, dx, dy = a * d - b * c, x - px, y - py
        x, y, angle =
            (d * dx - c * dy) / determinant, (-b * dx + a * dy) / determinant, angle - rotation
    end
    self.position[1], self.position[2], self.rotation = x, y, angle
end

function Node2D:isVisible()
    local node = self
    while node do
        if node.visible == false then
            return false
        end
        node = node.parent
    end
    return true
end

local Attachment2D = Node.define('Attachment2D', 'Node2D')
Attachment2D.mount = Node2D.mount

return Node2D
