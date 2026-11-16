-- Scene-owned factories (`register`/`spawn`) and scenes used as prefabs (`load`/`instantiate`, see
-- scenes/packed). Gameplay behavior stays outside the engine.
local Paths = require('../scenes.paths')

local Prefabs = {}
Prefabs.__index = Prefabs

function Prefabs.new(world)
    -- `manager` is the scene manager that loads packed scenes, `scene` the scene that holds this
    -- world; `setScene` sets both (a server world without a scene sets only `manager`).
    return setmetatable({ world = world, factories = {}, packed = {}, running = {} }, Prefabs)
end

function Prefabs:register(name, factory)
    assert(type(factory) == 'function' and not self.factories[name], 'Invalid or duplicate prefab')
    self.factories[name] = factory
    return self
end

function Prefabs:spawn(name, properties, parent)
    return assert(self.factories[name], 'Unknown prefab: ' .. tostring(name))(
        self.world,
        properties or {},
        parent
    )
end

-- What `load` returns: a packed scene bound to the world it instantiates into.
local Handle = {}
Handle.__index = Handle

function Handle:instantiate(properties, parent)
    return self.packed:instantiate(self.world, properties, parent)
end

function Handle:require(name)
    return self.packed:require(name)
end

-- Loads a scene (directory, archive, FileData, or a `scene://prefabs/name` / `shared://` path of
-- this scene's assets) as a packed scene; the same source is loaded once per world.
-- Where a source string points: `scheme://` paths resolve against this scene, other relative paths
-- are cleaned of `.` and `..` (the file system refuses them), absolute ones are left alone.
local function locate(source, paths)
    if type(source) ~= 'string' then
        return source
    elseif Paths.parse(source) then
        return Paths.resolve(source, paths)
    elseif source:match('^[/\\]') or source:match('^%a:') then
        return source
    end
    return Paths.normalize(source)
end

function Prefabs:load(source, paths)
    paths = paths or self.world.resources.paths
    local key = locate(source, paths)
    local packed = self.packed[key]
    if not packed then
        local manager = assert(self.manager, 'Packed scenes need a scene manager (prefabs:setScene)')
        packed = require('source.engine.scenes.packed').load(key, manager, paths and paths.shared, paths)
        self.packed[key] = packed
    end
    return setmetatable({ packed = packed, world = self.world }, Handle)
end

-- load + instantiate in one call.
function Prefabs:instantiate(source, properties, parent, paths)
    return self:load(source, paths):instantiate(properties, parent)
end

function Prefabs:setScene(scene)
    self.scene, self.manager = scene, scene.manager
end

-- A running prefab (runtime.lua) to update every frame (World3D:updateNodes).
function Prefabs:run(runtime)
    self.running[#self.running + 1] = runtime
end

function Prefabs:update(dt)
    local running = self.running
    for index = #running, 1, -1 do
        if running[index].released then
            table.remove(running, index)
        end
    end
    for index = 1, #running do
        local runtime = running[index]
        if not runtime.released then
            runtime:update(dt)
        end
    end
end

function Prefabs:release()
    for key, packed in pairs(self.packed) do
        packed:release()
        self.packed[key] = nil
    end
end

return Prefabs
