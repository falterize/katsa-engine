-- Stable IDs map to scene packages; display metadata lives in menu-settings.lua.
local Catalog = {
    entries = {
        { id = 'abilityRunner2D', path = 'game/scenes/abilityRunner2D' },
        { id = 'physics2D', path = 'game/scenes/physics2D' },
        { id = 'physicsMixed', path = 'game/scenes/physicsMixed' },
        { id = 'stareShooter', path = 'game/scenes/stareShooter' },
        { id = 'replicationLab', path = 'game/scenes/replicationLab' },
        { id = 'animationPhysicsLab', path = 'game/scenes/animationPhysicsLab' },
        { id = 'graphicsLab', path = 'game/scenes/graphicsLab' },
        { id = 'shaderLab', path = 'game/scenes/shaderLab' },
        { id = 'animationLab', path = 'game/scenes/animationLab' },
        { id = 'viewports', path = 'game/scenes/viewports' },
        { id = 'particles', path = 'game/scenes/particles' },
        { id = 'platformer', path = 'game/scenes/platformer' },
        { id = 'original', path = 'game/scenes/original' },
        { id = 'models', path = 'game/scenes/models' },
        { id = 'objects', path = 'game/scenes/objects' },
        { id = 'lights', path = 'game/scenes/lights' },
        { id = 'occlusion', path = 'game/scenes/occlusion' },
        { id = 'combined', path = 'game/scenes/combined' },
        { id = 'lights32', path = 'game/scenes/lights32' },
        { id = 'physics', path = 'game/scenes/physics' },
        { id = 'collisionModels', path = 'game/scenes/collisionModels' },
        { id = 'flyingAudio', path = 'game/scenes/flyingAudio' },
        { id = 'nightPlayer', path = 'game/scenes/nightPlayer' },
        { id = 'shadows', path = 'game/scenes/shadows' },
        { id = 'modelLab', path = 'game/scenes/modelLab' },
        { id = 'ikLab', path = 'game/scenes/ikLab' },
        { id = 'animationTreeLab', path = 'game/scenes/animationTreeLab' },
        { id = 'navMeshLab', path = 'game/scenes/navMeshLab' },
        { id = 'ribbonLab', path = 'game/scenes/ribbonLab' },
        { id = 'actorLab', path = 'game/scenes/actorLab' },
        { id = 'shapeKeysLab', path = 'game/scenes/shapeKeysLab' },
        { id = 'voxelWorld', path = 'game/scenes/voxelWorld' },
        { id = 'windowsLab', path = 'game/scenes/windowsLab' },
        { id = 'nodes', path = 'game/scenes/nodes' },
        { id = 'collisionBox', path = 'game/scenes/collisionBox' },
        { id = 'surfaceGallery', path = 'game/scenes/surfaceGallery' },
        { id = 'uiGallery', path = 'game/scenes/uiGallery' },
        { id = 'tileMapLab', path = 'game/scenes/tileMapLab' },
        { id = 'localizationLab', path = 'game/scenes/localizationLab' },
        { id = 'launcherShowcase', path = 'game/scenes/launcherShowcase' },
        { id = 'audioNodes', path = 'game/scenes/audioNodes' },
        { id = 'multiplayerCars', path = 'game/scenes/multiplayerCars' },
        { id = 'starterGame', path = 'game/scenes/starterGame', standalone = true },
        { id = 'nodeCatalog', path = 'game/scenes/nodeCatalog', interface = true },
    },
}

Catalog.byId = {}
for _, entry in ipairs(Catalog.entries) do
    Catalog.byId[entry.id] = entry
end

Catalog.byId.menu = { id = 'menu', path = 'game/scenes/menu', interface = true }

return Catalog
