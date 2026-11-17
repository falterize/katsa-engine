-- LODGroup: the level selection (pure), the node in a world, and the model import of -lodN nodes.
local Application = require('game.runtime.application')
local Plugins = require('source.engine.plugins')
local Models = require('source.engine.import.models')
local Schema = require('source.engine.editor.inspectors.schema')

local Lod = Plugins.require('lod')
local AutoLod, LodSelect = Lod.AutoLod, Lod.Select

local Module = {}

local function levelAt(group, world, camera, z)
    camera.position = { 0, 0, z }
    world.activeCamera:update(1280, 720)
    group:update(0.1)
    return group:getLevel()
end

function Module.run(self)
    local distance = LodSelect.thresholds('Distance', 3, {}, 2)
    local screen = LodSelect.thresholds('ScreenSize', 3, {}, 2)
    self:check(
        distance[1] == 12 and distance[2] == 30 and #distance == 2
            and screen[1] == 0.3 and screen[2] == 0.12 and #screen == 2,
        'Default thresholds follow the radius (distance) or are fixed fractions (screen size)'
    )
    local given = LodSelect.thresholds('Distance', 3, LodSelect.parse('20, 0, 90'), 2)
    self:check(
        given[1] == 20 and given[2] == 30 and given[3] == 90
            and LodSelect.format(LodSelect.parse({ 5, 10.5 })) == '5, 10.5',
        'Given thresholds win, a 0 falls back to the default, the last one hides; lists parse and print'
    )
    local th = { 10, 20 }
    self:check(
        LodSelect.level('Distance', 5, th, nil, 0) == 1
            and LodSelect.level('Distance', 10, th, nil, 0) == 2
            and LodSelect.level('Distance', 25, th, nil, 0) == 3
            and LodSelect.level('ScreenSize', 0.5, { 0.3, 0.1 }, nil, 0) == 1
            and LodSelect.level('ScreenSize', 0.2, { 0.3, 0.1 }, nil, 0) == 2
            and LodSelect.level('ScreenSize', 0.05, { 0.3, 0.1 }, nil, 0) == 3,
        'A value picks the level its thresholds put it on, in both modes'
    )
    self:check(
        LodSelect.level('Distance', 9.5, th, 2, 0.1) == 2
            and LodSelect.level('Distance', 8.9, th, 2, 0.1) == 1
            and LodSelect.level('Distance', 10.5, th, 1, 0.1) == 2
            and LodSelect.level('ScreenSize', 0.31, { 0.3, 0.1 }, 2, 0.1) == 2
            and LodSelect.level('ScreenSize', 0.34, { 0.3, 0.1 }, 2, 0.1) == 1,
        'Hysteresis: a coarser level starts at the threshold, a finer one only past it by the margin'
    )
    self:check(
        LodSelect.measure('Distance', 10, 0, 720, 2) == 20
            and LodSelect.measure('ScreenSize', 10, 144, 720, 2) == 0.1,
        'Bias above 1 lowers the detail sooner in both modes'
    )

    local scene = Application.new(self.manager, 'stareShooter')
    scene:load()
    local world = scene.world
    Plugins.activate(world, { 'lod' })
    local camera = world:create('Camera3D', { position = { 0, 0, -5 } })
    world:setCamera(camera)
    local group = world:create('LODGroup', { name = 'Tree', distances = { 10, 30, 80 } })
    local meshes = {}
    for index, name in ipairs({ 'High', 'Mid', 'Low' }) do
        meshes[index] = world:create('Mesh3D', { name = 'Tree' .. name, size = { 1, 1, 1 } }, group)
    end
    local at = {}
    for _, z in ipairs({ -5, -20, -50, -120 }) do
        at[#at + 1] = levelAt(group, world, camera, z)
    end
    self:check(
        at[1] == 0 and at[2] == 1 and at[3] == 2 and at[4] == -1,
        'A LODGroup switches level by camera distance and hides beyond the last number'
    )
    levelAt(group, world, camera, -20)
    self:check(
        not meshes[1].visible and meshes[2].visible and not meshes[3].visible,
        'Only the chosen level is visible'
    )
    group.mode = 'ScreenSize'
    group.screenSizes = '0.3, 0.1'
    local near = levelAt(group, world, camera, -3)
    local far = levelAt(group, world, camera, -60)
    self:check(
        near == 0 and far == 2,
        'ScreenSize mode follows how big the group looks, not how far it is'
    )
    group.forceLevel = 1
    self:check(levelAt(group, world, camera, -3) == 1, 'forceLevel pins a level for tests and tools')
    group.forceLevel = -1
    group.bias = 4
    self:check(
        levelAt(group, world, camera, -3) >= 1,
        'A bias above 1 gives the same view less detail'
    )
    local function shown(node, key)
        for _, name in ipairs(Schema.keys(node, {})) do
            if name == key then
                return true
            end
        end
        return false
    end
    self:check(
        shown(group, 'screenSizes') and not shown(group, 'distances') and shown(group, 'level')
            and shown(group, 'bias'),
        'The inspector lists the thresholds of the current mode, the bias and the level shown'
    )
    local clone = group:clone({ name = 'TreeCopy' })
    self:check(
        clone.mode == 'ScreenSize' and clone.screenSizes == group.screenSizes and #clone.children == 3,
        'A LODGroup clones with its settings and levels'
    )

    -- A model file whose node names carry -lodN becomes LODGroups on import.
    local base, level = AutoLod.parse('Rock-LOD2.001')
    self:check(
        base == 'Rock' and level == 2 and AutoLod.parse('Rock') == nil and AutoLod.parse('-lod1') == nil,
        'parse reads -lodN case-insensitively, ignores Blender copy suffixes and plain names'
    )
    local path = 'validation/tests/fixtures/models/lod.glb'
    local model = Models.load(path, world.resources)
    local _, root = Models.instantiate(world, model, { name = 'Lab', lod = { distances = '8, 20' } })
    local rockGroup, bodyGroup = root:find('RockLOD'), root:find('BodyLOD')
    self:check(
        #model.lodGroups == 2 and rockGroup and bodyGroup and #rockGroup.children == 3
            and #bodyGroup.children == 2,
        'Nodes named <name>, <name>-lod1 ... are collected into one LODGroup per name'
    )
    self:check(
        rockGroup.distances == '8, 20' and rockGroup.children[1].visible
            and not rockGroup.children[2].visible and not rockGroup.children[3].visible,
        'Import settings reach the group and only the most detailed level shows before a camera chooses'
    )
    rockGroup.forceLevel = 2
    rockGroup:update(0)
    self:check(
        rockGroup.children[3].visible and not rockGroup.children[1].visible,
        'A model level can be shown on its own'
    )
    local _, flat =
        Models.instantiate(world, Models.load(path, world.resources), { name = 'Flat', lod = false })
    self:check(flat:find('RockLOD') == nil and flat:find('Flat.Rock') ~= nil, 'lod = false skips the grouping')

    -- Both skinned levels use the one skeleton: the clip bends the same joint whichever is shown.
    local tip
    for _, node in ipairs(root:getDescendants()) do
        tip = tip or (node.name == 'Tip' and node)
    end
    local track = model.animator:load('Wave', { loop = true })
    track:play()
    local function bend()
        return tip.poseMatrix[1] -- cosine of the bend around Z: 1 at rest
    end
    local still = bend()
    bodyGroup.forceLevel = 0
    for _ = 1, 8 do
        world:updateNodes(0.05)
    end
    local first = bend()
    bodyGroup.forceLevel = 1
    for _ = 1, 8 do
        world:updateNodes(0.05)
    end
    local second = bend()
    self:check(
        bodyGroup.children[2].visible and first ~= still and second ~= first
            and bodyGroup.children[1].skin.definition == bodyGroup.children[2].skin.definition,
        'Skinned levels share one skeleton: the animation keeps playing when the level changes'
    )
    scene:release()
end

return Module
