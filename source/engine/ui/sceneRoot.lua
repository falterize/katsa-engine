-- Camera-free scenes still own their entire UI through World3D -> World2D.
local Root = {}

function Root.create(scene, width, height)
    scene.world = require('source.engine.world.world').new(
        scene.resources,
        require('source.engine.graphics.lighting.defaults').create()
    )
    scene.world.root.currentCamera = nil
    scene.ui = scene.world:create('World2D', { name = 'World2D', width = width, height = height })
    return scene.ui
end

return Root
