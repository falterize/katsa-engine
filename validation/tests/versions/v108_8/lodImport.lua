-- LOD import by names: suffixes in any order, level 0 conflicts, settings per group, levels with
-- different parents, and which levels keep a collider.
local AutoCollision = require('source.engine.import.autoCollision')
local Plugins = require('source.engine.plugins')
local ModelNodes = require('source.engine.import.modelNodes')
local Models = require('source.engine.import.models')
local World = require('source.engine.world.world')

local AutoLod = Plugins.require('lod').AutoLod

local Module = {}

-- A model made of nodes already in the world: parts name them, objects are the nodes.
local function fakeModel(world, entries)
    local root = world:create('Node3D', { name = 'Root' })
    local model, objects = { root = root, parts = {} }, {}
    for index, entry in ipairs(entries) do
        model.parts[index] = { name = entry.name }
        objects[index] = world:create(
            'Mesh3D',
            { name = entry.name, position = entry.position, size = { 1, 1, 1 } },
            entry.parent or root
        )
    end
    return model, objects
end

function Module.run(self)
    local parsed = ModelNodes.parse('Tree-lod1-col')
    local swapped = ModelNodes.parse('Tree-COL-LOD1.001')
    self:check(
        parsed.base == 'Tree' and parsed.level == 1 and parsed.collision == 'visible'
            and swapped.base == 'Tree' and swapped.level == 1 and swapped.collision == 'visible'
            and ModelNodes.parse('Tree-lod0-colonly').collision == 'only'
            and ModelNodes.parse('Tree') == nil and ModelNodes.parse('column') == nil,
        'Collision and LOD suffixes are read in either order, once each'
    )
    local base, level = AutoLod.parse('Tree-col-lod2')
    local colBase, kind, colLevel = AutoCollision.parse('Tree-col-lod2')
    self:check(
        base == 'Tree' and level == 2 and colBase == 'Tree' and kind == 'visible' and colLevel == 2
            and AutoLod.parse('Tree-col') == nil,
        'The two importers agree on the base name and the level of a combined name'
    )

    local world = World.new(self.manager.resources:scope())
    Plugins.activate(world, { 'lod' })
    world:createPhysics3D({ backend = 'oimo', gravity = { 0, 0, 0 } })
    local holder = world:create('Node3D', { name = 'Holder', position = { 10, 0, 0 } })
    local model, objects = fakeModel(world, {
        { name = 'Tree-lod0-col', parent = holder, position = { 1, 0, 0 } },
        { name = 'Tree-col-lod1', position = { 3, 0, 0 } },
        { name = 'Tree-lod2', parent = holder, position = { 0, 0, 0 } },
        { name = 'Tree-colonly', parent = holder, position = { 0, 0, 0 } },
        { name = 'Bush', position = { 0, 0, 0 } },
        { name = 'Bush-lod1', position = { 0, 0, 0 } },
    })
    local settings = { lod = { distances = '10, 20', groups = { Tree = { distances = '5, 9', fadeTime = 0.3 } } } }
    local bodies = AutoCollision.apply(world, model, objects, settings)
    local groups = AutoLod.apply(world, model, objects, settings)
    local tree, bush = holder:find('TreeLOD'), model.root:find('BushLOD')
    self:check(
        #bodies == 2 and #groups == 2 and #tree.children == 3,
        'Only the most detailed level and a -colonly proxy get colliders; the proxy is not a level'
    )
    self:check(
        tree.distances == '5, 9' and tree.fadeTime == 0.3 and bush.distances == '10, 20'
            and bush.fadeTime == 0,
        'Settings by name override the shared lod settings of one group'
    )
    local lod1 = world.byName['Tree-col-lod1']
    local lod0 = world.byName['Tree-lod0-col']
    self:check(
        tree.parent == holder and lod1.parent == tree
            and math.abs(lod1:getWorldMatrix()[4] - 3) < 1e-4
            and math.abs(lod0:getWorldMatrix()[4] - 11) < 1e-4,
        'Levels under different parents move into the group and keep their world position'
    )

    local other = World.new(self.manager.resources:scope())
    Plugins.activate(other, { 'lod' })
    local clash, clashObjects = fakeModel(other, { { name = 'Rock' }, { name = 'Rock-lod0' } })
    local ok, message = pcall(AutoLod.apply, other, clash, clashObjects, {})
    self:check(
        not ok and tostring(message):find('"Rock" and "Rock-lod0" are both level 0', 1, true),
        'A plain name and its -lod0 twin are a clear error that names both nodes'
    )
    local third = World.new(self.manager.resources:scope())
    Plugins.activate(third, { 'lod' })
    local copies, copyObjects =
        fakeModel(third, { { name = 'Pine' }, { name = 'Pine.001' }, { name = 'Pine-lod1' } })
    self:check(
        pcall(AutoLod.apply, third, copies, copyObjects, {}),
        'Blender copies of one name are not a conflict'
    )

    -- Without the plugin the engine knows nothing of LOD: no node type, no grouping on import.
    local bare = World.new(self.manager.resources:scope())
    local _, root = Models.instantiate(
        bare,
        Models.load('validation/tests/fixtures/models/lod.glb', bare.resources),
        { name = 'Bare' }
    )
    self:check(
        not pcall(bare.create, bare, 'LODGroup', {}) and root:find('RockLOD') == nil,
        'A scene that does not list the lod plugin has no LODGroup and no grouping on import'
    )
end

return Module
