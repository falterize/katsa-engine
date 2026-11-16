local Prefab = require('source.engine.scenes.packed.scene')

-- Content built once when the scene is packed.
local function build(scene)
    local world = scene.world
    local crate = world:create('Mesh3D', { name = 'Crate', size = { 1, 1, 1 } })
    world:create('SurfaceAppearance3D', { name = 'Skin', colorMap = 'stone' }, crate)
    world:create('SurfaceAppearance3D', { name = 'Dot', colorMap = './scene://textures/dot.png' }, crate)
    local lid = world:create('Mesh3D', { name = 'Lid', position = { 0, 0.6, 0 }, size = { 1, 0.2, 1 } }, crate)
    crate:setAttribute('Weight', 12)
    crate:setAttributeReference('Lid', lid)
    lid:addTag('Openable')
    world:create('Spinner', { name = 'Turntable', speed = 60 }, crate)
    world:create('Camera3D', { name = 'Cam', position = { 0, 2, -5 } }, crate)
    local board = world:create('BillboardUI', { name = 'Plate', size = { 0, 1, 0, 0.3 }, canvasSize = { 0, 100, 0, 30 } }, crate)
    world:create('Label', { name = 'PlateText', text = 'crate' }, board)
    local surface = world:create('SurfaceUI', { name = 'Screen' }, crate)
    world:create('Label', { name = 'ScreenText', text = 'screen' }, surface)
    local ui = scene.root:find('World3D/World2D')
    world:create('Node2D', { name = 'Marker', position = { 3, 4 } })
    ui:button({ name = 'CrateButton', text = 'Crate', size = { 0, 80, 0, 30 } }, ui.content)
end

-- Scripts that run for every copy.
return Prefab.define(build, {
    create = function(scene)
        scene.node:setAttribute('Created', true)
        scene.world:create('Mesh3D', { name = 'Made', size = { 1, 1, 1 } }) -- lands under the copy
        scene.world:create('Label', { name = 'Hello', text = 'hi' }) -- lands in the copy's World2D
        return { frames = 0 }
    end,
    update = function(state, dt)
        state.frames = state.frames + 1
    end,
    destroy = function(state)
        _G.CRATE_DESTROYED = (_G.CRATE_DESTROYED or 0) + 1
    end,
})
