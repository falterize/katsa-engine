-- A scene used as a prefab: loaded from a folder or an archive, instantiated many times.
local Application = require('game.runtime.application')

local Module = {}

local FOLDER = 'validation/tests/fixtures/prefabs/crate'
local ARCHIVE = 'validation/tests/fixtures/prefabs/crateArchive.zip'

function Module.run(self)
    local scene = Application.new(self.manager, 'stareShooter')
    scene:load()
    local world = scene.world
    local prefabs = world.prefabs
    local crate = prefabs:load(FOLDER)
    local a = crate:instantiate({ name = 'A', position = { 1, 2, 3 } })
    local b = crate:instantiate({
        name = 'B',
        overrides = { ['Crate/Lid'] = { size = { 2, 0.2, 2 } } },
    })
    self:check(
        a.className == 'Node3D' and a.position[2] == 2 and a:find('Crate/Lid') and b:find('Crate'),
        'A scene folder instantiates as a Node3D holding what its World3D built'
    )
    self:check(
        a:find('Crate') ~= b:find('Crate') and b:find('Crate/Lid').size[1] == 2
            and a:find('Crate/Lid').size[1] == 1,
        'Instances are independent and overrides reach nodes by path'
    )
    self:check(
        a:getAttribute('ScenePath') ~= nil
            and not a:find('Environment') and not a:find('World2D') and a:find('Crate') ~= nil,
        'The scene\'s own Environment and overlay container are not copied (only what it put in them)'
    )
    local crateNode = a:find('Crate')
    self:check(
        crateNode:getAttribute('Weight') == 12
            and crateNode:getAttribute('Lid') == a:find('Crate/Lid')
            and a:find('Crate/Lid'):hasTag('Openable'),
        'Attributes, node references and tags are rebuilt inside the instance'
    )
    self:check(
        a:find('Crate/Skin').colorMap == 'crate:stone'
            and world.resources.manifest['crate:stone'].filter == 'nearest',
        'The scene\'s own resource names are registered in the importing world'
    )
    self:check(
        crate:require('scripts.data').title == 'Crate'
            and prefabs:load(FOLDER).packed == crate.packed,
        'A packed scene is loaded once and exposes its modules'
    )
    local turntable = a:find('Crate/Turntable')
    world:updateNodes(1)
    self:check(
        turntable and turntable.speed == 60 and math.abs(turntable.rotation[2] - 60) < 1e-6,
        'Node types and scripts of the prefab scene run in the world that holds a copy'
    )
    local camera = world.activeCamera
    local copy = crate:instantiate({ name = 'D' })
    self:check(
        copy:find('Crate/Cam') and copy:find('Crate/Cam').className == 'Camera3D'
            and world.activeCamera == camera,
        'Cameras are copied and never become the current camera'
    )
    self:check(
        copy:find('Crate/Plate/PlateText').text == 'crate'
            and copy:find('Crate/Screen/ScreenText').text == 'screen'
            and a:find('Crate/Plate/PlateText') ~= copy:find('Crate/Plate/PlateText'),
        'BillboardUI and SurfaceUI keep their UI children in every copy'
    )
    local overlay = world.uis[1].content
    local buttons = 0
    for _, node in ipairs(overlay.children) do
        buttons = buttons + (node.name == 'CrateButton' and 1 or 0)
    end
    copy:destroy()
    local left = 0
    for _, node in ipairs(overlay.children) do
        left = left + (node.name == 'CrateButton' and 1 or 0)
    end
    self:check(buttons == 3 and left == 2, 'The scene overlay (World2D) is shown on the world\'s and leaves with the copy')
    self:check(
        a:getAttribute('Created') == true and a:find('Made') ~= nil,
        'The prefab scene\'s create hook runs for each copy and builds into it'
    )
    world:updateNodes(0.1)
    world:updateNodes(0.1)
    self:check(
        a:getAttribute('Ticks') == 3 and b:getAttribute('Ticks') == 3 and _G.CRATE_DESTROYED == 1,
        'update hooks and systems/ modules run for every living copy'
    )
    self:check(
        a:find('Crate/Dot').colorMap == 'validation/tests/fixtures/prefabs/crate/assets/textures/dot.png',
        'A "./scene://" path points at the prefab scene\'s own assets'
    )
    local outer = prefabs:instantiate('validation/tests/fixtures/prefabs/outer', { name = 'Outer' })
    self:check(
        outer:find('Inner/Tile/Skin').colorMap
            == 'validation/tests/fixtures/prefabs/outer/assets/textures/outer.png',
        'Nested prefabs: "../scene://" points at the scene that loaded the prefab'
    )
    outer:destroy()
    local fromArchive = prefabs:instantiate(ARCHIVE, { name = 'C' })
    self:check(
        fromArchive:find('Crate/Lid') ~= nil,
        'An archive works like a folder'
    )
    local avatar = prefabs:instantiate('game/scenes/replicationLab/assets/prefabs/avatar')
    local character = avatar:find('Character')
    self:check(
        character.model and character.model.animator and avatar:find('Character/Tree'),
        'An imported model is imported again (skeleton and animation work) next to its scene nodes'
    )
    a:destroy()
    b:destroy()
    fromArchive:destroy()
    avatar:destroy()
    self:check(_G.CRATE_DESTROYED == 4, 'destroy hooks run when copies are destroyed')
    scene:release()
end

return Module
