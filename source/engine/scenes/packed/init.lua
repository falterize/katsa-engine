local Loader = require('../loader')
local Host = require('../host')
local Describe = require('./describe')
local Build = require('./build')
local Runtime = require('./runtime')

-- A scene used as a prefab (like a Godot PackedScene). The scene is run once, in a private world;
-- what it built under its World3D (everything but the world's own Environment, camera and
-- overlay) is kept as a template. `instantiate` builds a fresh copy of that content under a Node3D
-- in any world, so the scene can be a folder or an archive like every other scene.
--
--   local enemy = world.prefabs:load('scene://prefabs/enemy')
--   local copy = enemy:instantiate({ name = 'Enemy1', position = { 10, 0, 5 } })
--   copy:find('Body/Head').color = { 1, 0, 0 }
local Packed = {}
Packed.__index = Packed

-- source: a scene directory, archive path or FileData. manager: the scene manager (the packed
-- scene is loaded by the same machinery as any scene); shared: the shared assets root; parent: the
-- asset roots of the scene that loads this one (what `../scene://x` points at).
function Packed.load(source, manager, shared, parent)
    local package = Loader.open(source, nil, shared)
    package.paths.parent = parent
    local host = Host.new(manager, package, { prefab = true })
    local ok, message = pcall(host.load, host)
    if not ok then
        host:release()
        error(message, 0)
    end
    -- Keep the package (its modules and archive mount) alive for the template's lifetime.
    package:retain()
    local template =
        Describe.children(host.world._node, host.baseline, host.resources, package.id)
    local lifecycle = package:require('main')
    local scripted = lifecycle.build ~= nil
        and (lifecycle.scripted or katsa.filesystem.getInfo(package.root .. '/systems', 'directory') ~= nil)
    host:release()
    return setmetatable(
        { package = package, template = template, source = source, scripted = scripted },
        Packed
    )
end

-- The node types and plugins the scene declares (`settings.nodes`, `settings.plugins`) must exist in
-- the world that receives a copy; their `update` and `start` hooks then run as for any node.
function Packed:prepare(world)
    local prepared = world._packedPrepared or {}
    world._packedPrepared = prepared
    -- Once per scene id: the same scene loaded from a folder and from an archive declares the same types.
    if prepared[self.package.id] then
        return
    end
    prepared[self.package.id] = true
    local settings = self.package.settings
    self.package:registerNodes(world, settings.nodes or {})
    require('source.engine.plugins').activateFor(world, settings.plugins)
end

-- Creates a copy of the content under a new Node3D and returns it. `properties` are the Node3D's
-- (name, position, rotation, scale ...); `overrides = { ['Body/Head'] = { color = ... } }` sets
-- properties of nodes inside the copy by their path. `parent` defaults to the world. Cameras are
-- copied but never become the current camera. The scene's World2D nodes are copied as World2D nodes
-- inside the copy's Node3D (they belong to the world above it) and go away with the copy. When the scene has scripts
-- (see runtime.lua) they start here and run for as long as the copy lives.
function Packed:instantiate(world, properties, parent)
    assert(not self.released, 'Packed scene is released')
    self:prepare(world)
    properties = properties or {}
    local overrides = properties.overrides
    local values = {}
    for key, value in pairs(properties) do
        if key ~= 'overrides' and key ~= 'parent' then
            values[key] = value
        end
    end
    values.name = values.name or self.package.id
    local root = world:create('Node3D', values, parent or properties.parent or world._node)
    root:setAttribute('ScenePath', tostring(self.package.root))
    local camera = world.activeCamera
    local _, worlds = Build.nodes(world, self.template, root)
    world.activeCamera = camera
    local main
    for _, item in ipairs(worlds) do
        main = main or (item.main and item.node)
    end
    for path, changes in pairs(overrides or {}) do
        local target = assert(root:find(path), 'Override path not found: ' .. path)
        for key, value in pairs(changes) do
            target[key] = value
        end
    end
    local runtime = self.scripted and Runtime.start(self, world, root, world.prefabs.scene, main)
    if runtime then
        world.prefabs:run(runtime)
    end
    return root
end

-- The packed scene's own modules (`scene.`-relative names), e.g. data a scene keeps next to its nodes.
function Packed:require(name)
    return self.package:require(name)
end

function Packed:release()
    if not self.released then
        self.released = true
        self.package:release()
    end
end

return Packed
