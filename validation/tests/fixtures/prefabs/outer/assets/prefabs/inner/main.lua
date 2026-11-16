return require('source.engine.scenes.packed.scene').define(function(scene)
    local tile = scene.world:create('Mesh3D', { name = 'Tile', size = { 1, 1, 1 } })
    -- '../scene://' is an asset of the scene that loaded this one (outer).
    scene.world:create('SurfaceAppearance3D', { name = 'Skin', colorMap = '../scene://textures/outer.png' }, tile)
end)
