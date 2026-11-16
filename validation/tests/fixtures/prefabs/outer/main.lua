return require('source.engine.scenes.packed.scene').define(function(scene)
    -- A prefab inside a prefab: its path is relative to this scene's assets.
    scene.world.prefabs:instantiate('./scene://prefabs/inner', { name = 'Inner' })
end)
