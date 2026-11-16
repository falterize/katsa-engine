-- A scene used as a prefab: loaded from a folder or an archive, instantiated many times.
local Application = require('game.runtime.application')
local Paths = require('source.engine.scenes.paths')

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
            and not a:find('Environment') and a:find('World2D') ~= nil and a:find('Crate') ~= nil,
        'The scene\'s own Environment is not copied; its World2D is, inside the copy'
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
    local function copies()
        local count, names = 0, {}
        for _, ui in ipairs(world.uis) do
            for _, node in ipairs(ui.content.children) do
                if node.name == 'CrateButton' then
                    count, names[ui.parent.name] = count + 1, true
                end
            end
        end
        return count, names
    end
    local ownUi
    for _, ui in ipairs(world.uis) do
        ownUi = ownUi or (ui.parent == a and ui)
    end
    local marker = ownUi and ownUi:find('Marker')
    self:check(
        marker and marker.className == 'Node2D' and marker.position[1] == 3
            and ownUi.content:find('Hello') ~= nil,
        'The copied World2D keeps its Node2D children, and UI a script creates lands in it'
    )
    local holder = world:create('Node3D', { name = 'Holder' })
    local inside = world:create('World2D', { name = 'Inside' }, holder)
    local listed = world.uis[#world.uis] == inside
    local rejected = not pcall(world.create, world, 'World2D', {}, inside.content)
    holder:destroy()
    local gone = true
    for _, ui in ipairs(world.uis) do
        gone = gone and ui ~= inside
    end
    self:check(
        inside.parent ~= world._node and listed and rejected and inside.destroyed and gone,
        'A World2D can sit inside any node of its World3D (not inside a widget) and leaves with it'
    )
    local before, names = copies()
    local own = copy:find('Crate') and world.uis[#world.uis]
    copy:destroy()
    local after = copies()
    self:check(
        before == 3 and after == 2 and names.A and names.B and names.D and own.destroyed,
        'The scene\'s World2D is copied as a World2D inside each copy and leaves with it'
    )
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
    self:check(
        a:getAttribute('Icon') == 'validation/tests/fixtures/prefabs/crate/assets/textures/dot.png',
        'A script resolves a prefab path it assigns later with scene.resources:canonical'
    )
    local paths = world.resources.paths
    self:check(
        world.resources:canonical('crate://textures/dot.png')
            == 'validation/tests/fixtures/prefabs/crate/assets/textures/dot.png'
            and Paths.parse('my-scene_2://x') == 'my-scene_2',
        'A loaded prefab answers to "<id>://" for its assets from anywhere in the world'
    )
    prefabs:load(FOLDER, { name = 'box' })
    local clash = pcall(prefabs.load, prefabs, 'validation/tests/fixtures/prefabs/outer', { name = 'box' })
    self:check(
        world.resources:canonical('box://textures/dot.png') == world.resources:canonical('crate://textures/dot.png')
            and not clash,
        'A prefab may take its own name; one name cannot stand for two scenes'
    )
    local outer = prefabs:instantiate('validation/tests/fixtures/prefabs/outer', { name = 'Outer' })
    self:check(
        outer:find('Inner/Tile/Skin').colorMap
            == 'validation/tests/fixtures/prefabs/outer/assets/textures/outer.png',
        'Nested prefabs: "../scene://" points at the scene that loaded the prefab'
    )
    outer:destroy()
    local fromArchive = prefabs:instantiate(ARCHIVE, { name = 'C' }, nil, { name = 'crateZip' })
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
