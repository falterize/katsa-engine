local Node = require('../core.baseNode')
local M = require('../../math.math3d')

local Class = Node.define('Button3D', 'Node')

require('../../components.ordering.priority').describe(Class)

function Class.initialize(self)
    self.radius = self.radius or 32
    require('source.engine.components.ordering.priority').normalize(self)
    self.enabled = self.enabled ~= false
    -- True: the whole model below the target is clickable. False: only the target node itself.
    self.includeDescendants = self.includeDescendants ~= false
    self._requestedAdornee = rawget(self, 'adornee')
    rawset(self, 'adornee', nil)
end

function Class.mount(world, properties, parent)
    local node = Node.new('Button3D', properties, parent)
    node._world = world
    require('source.engine.world.surfaces.support').initialize(node, node._requestedAdornee)
    node._requestedAdornee = nil
    world.buttons3D = world.buttons3D or {}
    world._button3DCount = (world._button3DCount or 0) + 1
    node._order = world._button3DCount -- creation order: detectors fire in it
    world.buttons3D[node] = true
    node:onDestroy(function()
        world.buttons3D[node] = nil
    end)
    return node
end

function Class:setAdornee(node)
    assert(node == nil or node:isA('Node3D'), 'Button3D Adornee must be a Node3D')
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
        'Button3D Radius must be finite and nonnegative'
    )
    local object = self:getTarget()
    if
        not object
        or not object:isA('Node3D')
        or object.visible == false
        or object.isVisible and not object:isVisible()
    then
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

-- True when `mesh` is the target or (with `includeDescendants`) lies anywhere below it, so one
-- button on a Node3D covers a whole model of many parts.
function Class:contains(mesh)
    local target = self:getTarget()
    if not self.includeDescendants then
        return mesh == target
    end
    while mesh do
        if mesh == target then
            return true
        end
        mesh = mesh.parent
    end
    return false
end

require('../../components.interaction.pointerVerbs').install(Class)

return Class
