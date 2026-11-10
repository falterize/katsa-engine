local Node = require('../core.baseNode')
local M = require('../../math.math3d')

local Class = Node.define('ClickDetector3D', 'Node')

function Class.initialize(self)
    self.radius = self.radius or 32
    self.enabled = self.enabled ~= false
    self._requestedAdornee = rawget(self, 'adornee')
    rawset(self, 'adornee', nil)
end

function Class.mount(world, properties, parent)
    local node = Node.new('ClickDetector3D', properties, parent)
    node._world = world
    require('source.engine.world.surfaces.support').initialize(node, node._requestedAdornee)
    node._requestedAdornee = nil
    world.clickDetectors = world.clickDetectors or {}
    world.clickDetectors[node] = true
    node:onDestroy(function()
        world.clickDetectors[node] = nil
    end)
    return node
end

function Class:setAdornee(node)
    assert(node == nil or node:isA('Mesh3D'), 'ClickDetector3D Adornee must be a Mesh3D')
    return require('source.engine.world.surfaces.support').set(self, node)
end

function Class:getTarget()
    if self._adorneeLost then
        return
    end
    return self.adornee or self.parent
end

function Class:canActivate()
    if not self.enabled or self.destroyed or self._destroying then
        return false
    end
    assert(
        type(self.radius) == 'number' and self.radius >= 0 and self.radius < math.huge,
        'ClickDetector3D Radius must be finite and nonnegative'
    )
    local object = self:getTarget()
    if not object or not object:isA('Mesh3D') or not object:isVisible() then
        return false
    end
    local world = self._sceneWorld or object._world
    local source = self.positionSource or world.interactionSource
    if
        not source
        or source.destroyed
        or not source.getWorldPosition
        or (source._world or source._sceneWorld) ~= world
    then
        return false
    end
    -- Distance targets the Mesh3D spatial origin, not its rendered bounding-box edge.
    return M.distanceSquared(source:getWorldPosition(), object:getWorldPosition())
        <= self.radius ^ 2
end

-- Fires `clicked` from code. `force` skips the distance and visibility checks (a scripted or
-- on-screen-button press): only an enabled, live detector still answers.
function Class:activate(pointerId, force)
    local alive = self.enabled and not self.destroyed and not self._destroying
    if force and alive or not force and self:canActivate() then
        self:emit('clicked', pointerId, self:getTarget())
        return true
    end
    return false
end

return Class
