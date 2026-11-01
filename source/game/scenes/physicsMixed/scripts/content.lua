local Content = {}

function Content.create(scene)
    scene.ui:create('Camera2D', { name = 'Camera2D', position = { 640, -360 }, zoom = 1 })
    local physics = scene:createPhysics2D()
    scene.ui.autoUpdatePhysics = false
    scene.statsHelp = '2D shapes, joints and triggers. Use the on-screen controls; F3: Stats.'
    scene.ui.layoutMode = 'Fit'
    local state = { scene = scene, physics = physics }
    scene.package:require('scripts.builders.playground').create(state)
    scene.package:require('scripts.builders.spatial').create(state)
    return state
end

return Content
