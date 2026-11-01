local Debug = {}

function Debug.toggle(scene)
    if scene.freeDebugCamera then
        local state = scene.freeDebugCamera
        scene.freeDebugCamera = nil
        state.camera:destroy()
        if not state.previous.destroyed then
            scene.camera = scene.world:setCamera(state.previous)
        else
            scene.camera = scene.world.activeCamera
        end
        scene.input:reset()
        return false
    end
    local previous = scene.world.activeCamera
    local p, r = require('source.engine.math.affine').decompose(previous:getWorldMatrix())
    r[1], r[2] = -r[1], -r[2]
    local camera = scene.world:addCamera({
        name = 'FreeDebugCamera',
        position = p,
        rotation = r,
        layerGroup = previous.layerGroup,
        drawDistance = previous.drawDistance,
        -- Keep the scene's projection so an orthographic view stays orthographic while flying.
        projectionMode = previous.projectionMode,
        orthoSize = previous.orthoSize,
        orthoNear = previous.orthoNear,
        zoom = previous.zoom,
    })
    scene.freeDebugCamera = { camera = camera, previous = previous }
    scene.camera = scene.world:setCamera(camera)
    scene.input:reset()
    return true
end

return Debug
