local Mesh = require('source.engine.composition.mesh')

local Content = {}

function Content.create(scene)
    local Saves = scene.package:require('scripts.data.saves')
    scene.camera.position = { 0, 3, -8 }
    scene.camera.rotation = { -12, 0, 0 }
    local cube = Mesh.create(scene.world, {
        name = 'Cube',
        position = { 0, 0, 0 },
        size = { 2, 2, 2 },
        color = { 0.25, 0.7, 0.9 },
        surfaceAppearance = { colorMap = 'white' },
    })
    local data = scene.data:scope('game')
    local saved, metadata = Saves.read(data, 'progress.json', 'progress', {
        defaults = { score = 0 },
    })
    local preferences, settingsError = Saves.read(data, 'settings.json', 'settings', {
        defaults = { rotationEnabled = true },
    })
    assert(preferences, settingsError)
    -- Failed reads are surfaced rather than silently replacing damaged progress.
    return {
        scene = scene,
        cube = cube,
        data = data,
        saved = saved,
        saveError = not saved and metadata or nil,
        preferences = preferences,
    }
end

return Content
