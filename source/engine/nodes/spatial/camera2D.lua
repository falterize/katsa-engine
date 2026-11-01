local Node = require('source.engine.nodes.core.baseNode')
local Spatial = require('source.engine.nodes.spatial.node2D')

local Camera2D = Node.define('Camera2D', 'Node2D')
Camera2D.propertySchema = {
    layerGroup = {},
    zoom = { min = 0.001 },
    followTarget = { kind = 'node', nodeClass = 'Node2D' },
    fov = { min = 1, max = 179 },
    referenceHeight = { min = 1 },
    drawDistance = { min = 0 },
    offset = { kind = 'vector' },
}

function Camera2D.initialize(self)
    self.layerGroup = self.layerGroup or 'Default'
    self.zoom = self.zoom or 1
    self.fov = self.fov or 60
    self.referenceHeight = self.referenceHeight or 720
    self.drawDistance = self.drawDistance or 100000
    self.offset = self.offset or { 0, 0 }
end

function Camera2D.mount(context, properties, parent)
    local node = Spatial.mount(context, properties, parent)
    if properties.current ~= false then
        node._plane:setCurrentCamera(node)
    end
    node:onDestroy(function()
        if node._plane.currentCamera == node then
            node._plane.currentCamera = nil
        end
    end)
    return node
end

function Camera2D:updateFollow()
    local target = self.followTarget
    if not target or target.destroyed then
        return
    end
    assert(target._plane == self._plane, 'Camera2D target must belong to the same World2D')
    -- Follow the pose that is drawn: interpolated bodies show a blend of the last two solver
    -- steps, and a camera locked to the raw step pose would drift against them each frame.
    local x, y = require('source.engine.ui.spatial.plane').pose(target)
    local _, _, angle = self:getWorldPose()
    self:setWorldPose(x + self.offset[1], y + self.offset[2], angle)
end

function Camera2D:projectionScale(height)
    assert(self.zoom > 0 and self.zoom < math.huge, 'Camera2D zoom must be finite and positive')
    assert(self.fov > 0 and self.fov < 180, 'Camera2D fov must be between zero and 180 degrees')
    assert(self.referenceHeight > 0, 'Camera2D referenceHeight must be positive')
    return self.zoom
        * height
        / self.referenceHeight
        * math.tan(math.rad(30))
        / math.tan(math.rad(self.fov / 2))
end

function Camera2D:getFocalLength()
    return self.referenceHeight / (2 * math.tan(math.rad(self.fov / 2)))
end

function Camera2D:setFocalLength(value)
    assert(value > 0 and value < math.huge, 'Camera2D focal length must be finite and positive')
    self.fov = math.deg(2 * math.atan(self.referenceHeight / (2 * value)))
end

function Camera2D:getVisibleSize(width, height)
    local scale = self:projectionScale(height)
    return width / scale, height / scale
end

function Camera2D:apply(width, height)
    local x, y, angle = self:getWorldPose()
    local g = katsa.graphics
    g.translate(width / 2, height / 2)
    local scale = self:projectionScale(height)
    g.scale(scale, -scale)
    g.rotate(-math.rad(angle))
    g.translate(-x, -y)
end

function Camera2D:screenToWorld(x, y, width, height)
    local cx, cy, angle = self:getWorldPose()
    local c, s, scale =
        math.cos(math.rad(angle)), math.sin(math.rad(angle)), self:projectionScale(height)
    x, y = (x - width / 2) / scale, -(y - height / 2) / scale
    return cx + x * c - y * s, cy + x * s + y * c
end

function Camera2D:worldToScreen(x, y, width, height)
    local cx, cy, angle = self:getWorldPose()
    local c, s, dx, dy = math.cos(math.rad(-angle)), math.sin(math.rad(-angle)), x - cx, y - cy
    local scale = self:projectionScale(height)
    return width / 2 + (dx * c - dy * s) * scale, height / 2 - (dx * s + dy * c) * scale
end

function Camera2D:project(point)
    return self:worldToScreen(point[1], point[2], self._plane.width, self._plane.height)
end

function Camera2D:unproject(x, y)
    local wx, wy = self:screenToWorld(x, y, self._plane.width, self._plane.height)
    return { wx, wy }
end

return Camera2D
