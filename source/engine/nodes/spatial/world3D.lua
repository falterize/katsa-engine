local ipairs = require('../../math.array').ipairs
local Node = require('../core.baseNode')

local C = Node.define('World3D', 'Node3D')
C.propertySchema = {
    gravity = { min = 0 },
    gravityDirection = {
        kind = 'vector',
    },
}

function C.initialize(self)
    require('source.engine.world.gravity').initialize(self, 3)
    self.timeScale = self.timeScale or 1
end

function C.mount(context, properties, parent)
    assert(
        parent and parent:isA('ViewportFrame'),
        'Additional World3D roots require a ViewportFrame parent'
    )
    assert(not parent:getWorld(), 'ViewportFrame owns at most one World3D')
    local scope = context.resources:scope()
    local world = require('source.engine.world.world').new(
        scope,
        require('source.engine.graphics.lighting.defaults').create()
    )
    world.hostWorld = context._world or context._sceneWorld
    -- The viewport loads packed scenes with the same scene manager as the world that holds it.
    local hostScene = world.hostWorld and world.hostWorld.prefabs
    if hostScene and hostScene.manager then
        world.prefabs.manager, world.prefabs.scene = hostScene.manager, hostScene.scene
    end
    world._node.name = properties.name or 'ViewportWorld'
    world._node.timeScale = properties.timeScale or properties.TimeScale or 1
    if
        properties.gravity ~= nil
        or properties.Gravity ~= nil
        or properties.gravityDirection
        or properties.GravityDirection
    then
        world._node.gravity = properties.gravity or properties.Gravity or world._node.gravity
        world._node.gravityDirection = properties.gravityDirection
            or properties.GravityDirection
            or world._node.gravityDirection
        world._node._gravityConfigured = true
    end
    world._node._worldBoundary = true
    world._node.parent = parent
    world._node._ownsScope = true
    world._node:onDestroy(function()
        world.prefabs:release()
        world.animations:release()
        world.nodeTree:release()
        if world.renderer then
            world.renderer:release()
            world.renderer = nil
        end
        scope:release()
    end)
    return world._node
end

function C:create(name, properties, parent)
    return self._world:create(name, properties, parent)
end

function C:setCurrentCamera(camera)
    if camera == nil then
        self._world.activeCamera = nil
        return
    end
    return self._world:setCamera(camera)
end

function C:update(dt)
    local world = self._world
    local realDt = dt
    world.frameRealDelta = realDt
    dt = require('source.engine.world.clock').delta(self, dt)
    if world.physics then
        world.physics:update(dt)
    end
    world.viewportTime = (world.viewportTime or 0) + dt
    for _, ui in ipairs(world.uis or {}) do
        ui:update(realDt, realDt)
    end
    world:updateNodes(dt)
    world:updateCameras(dt)
end

return C
