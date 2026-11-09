-- Stable IDs map to scene packages; display metadata lives in settings.lua.
local Catalog = {
    entries = {
        { id = 'abilityRunner2D', path = 'source/game/scenes/abilityRunner2D' },
        { id = 'physics2D', path = 'source/game/scenes/physics2D' },
        { id = 'physicsMixed', path = 'source/game/scenes/physicsMixed' },
        { id = 'stareShooter', path = 'source/game/scenes/stareShooter' },
        { id = 'animationPhysicsLab', path = 'source/game/scenes/animationPhysicsLab' },
        { id = 'graphicsLab', path = 'source/game/scenes/graphicsLab' },
        { id = 'shaderLab', path = 'source/game/scenes/shaderLab' },
        { id = 'animationLab', path = 'source/game/scenes/animationLab' },
        { id = 'viewports', path = 'source/game/scenes/viewports' },
        { id = 'particles', path = 'source/game/scenes/particles' },
        { id = 'platformer', path = 'source/game/scenes/platformer' },
        { id = 'original', path = 'source/game/scenes/original' },
        { id = 'models', path = 'source/game/scenes/models' },
        { id = 'objects', path = 'source/game/scenes/objects' },
        { id = 'lights', path = 'source/game/scenes/lights' },
        { id = 'occlusion', path = 'source/game/scenes/occlusion' },
        { id = 'combined', path = 'source/game/scenes/combined' },
        { id = 'lights32', path = 'source/game/scenes/lights32' },
        { id = 'physics', path = 'source/game/scenes/physics' },
        { id = 'collisionModels', path = 'source/game/scenes/collisionModels' },
        { id = 'flyingAudio', path = 'source/game/scenes/flyingAudio' },
        { id = 'nightPlayer', path = 'source/game/scenes/nightPlayer' },
        { id = 'shadows', path = 'source/game/scenes/shadows' },
        { id = 'modelLab', path = 'source/game/scenes/modelLab' },
        { id = 'ikLab', path = 'source/game/scenes/ikLab' },
        { id = 'animationTreeLab', path = 'source/game/scenes/animationTreeLab' },
        { id = 'navMeshLab', path = 'source/game/scenes/navMeshLab' },
        { id = 'ribbonLab', path = 'source/game/scenes/ribbonLab' },
        { id = 'actorLab', path = 'source/game/scenes/actorLab' },
        { id = 'shapeKeysLab', path = 'source/game/scenes/shapeKeysLab' },
        { id = 'windowsLab', path = 'source/game/scenes/windowsLab' },
        { id = 'nodes', path = 'source/game/scenes/nodes' },
        { id = 'collisionBox', path = 'source/game/scenes/collisionBox' },
        { id = 'surfaceGallery', path = 'source/game/scenes/surfaceGallery' },
        { id = 'uiGallery', path = 'source/game/scenes/uiGallery' },
        { id = 'tileMapLab', path = 'source/game/scenes/tileMapLab' },
        { id = 'localizationLab', path = 'source/game/scenes/localizationLab' },
        { id = 'launcherShowcase', path = 'source/game/scenes/launcherShowcase' },
        { id = 'audioNodes', path = 'source/game/scenes/audioNodes' },
        { id = 'multiplayerCars', path = 'source/game/scenes/multiplayerCars' },
        { id = 'starterGame', path = 'source/game/scenes/starterGame', standalone = true },
        { id = 'nodeCatalog', path = 'source/game/scenes/nodeCatalog', interface = true },
    },
}

Catalog.byId = {}
for _, entry in ipairs(Catalog.entries) do
    Catalog.byId[entry.id] = entry
end

Catalog.byId.menu = { id = 'menu', path = 'source/game/scenes/menu', interface = true }

return Catalog
