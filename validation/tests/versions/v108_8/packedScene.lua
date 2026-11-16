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
            and not a:find('Environment', true) and not a:find('World2D', true),
        'The scene\'s Environment, camera and overlay are not copied'
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
    scene:release()
end

return Module
