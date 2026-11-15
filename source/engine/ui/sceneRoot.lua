local RootNode = require('../scenes.rootNode')

-- Camera-free scenes still own their entire UI through World3D -> World2D, under a Root node
-- (`scene.root`) like every other scene.
local Root = {}

function Root.create(scene, width, height)
    scene.world = require('source.engine.world.world').new(
        scene.resources,
        require('source.engine.graphics.lighting.defaults').create()
    )
    scene.root = RootNode.create(scene.world)
    scene.world._node.currentCamera = nil
    scene._ui = scene.world:create('World2D', { name = 'World2D', width = width, height = height })
    return scene._ui
end

return Root
