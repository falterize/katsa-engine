local Node = require('source.engine.nodes')
local Resource = require('./resource')
local Build = require('./build')

-- The `scene.world` a prefab's scripts see: the world of the scene that holds the copy, with two
-- differences. `create` puts spatial nodes under the copy's own Node3D unless a parent is given
-- (overlay and 2D nodes keep their usual place), and rewrites the prefab's resource names
-- (`scene://`, `./scene://`, `../scene://`, manifest aliases) so the world finds its assets.
-- `prefabs` resolves paths against the prefab's scene. Everything else is the real world.
local WorldView = {}

local function ownsSpace(world, className)
    local types = Node.getClass(className, world)._types
    return not (types.UINode or types.Node2D or types.Constraint2D or types.World2D or types.Environment)
end

-- world: the real world. scope: { node = the copy's Node3D, context = Resource context,
-- paths = the prefab scene's asset roots }.
function WorldView.new(world, scope)
    local wrappers = {}
    local view = {}

    function view.create(_, className, properties, parent)
        if parent == nil and ownsSpace(world, className) then
            parent = scope.node
        end
        properties = Resource.deep(properties or {}, scope.context)
        Resource.register(world, scope.context.aliases)
        return Build.create(world, className, properties, parent)
    end

    local prefabs = world.prefabs
    view.prefabs = {
        load = function(_, source)
            return prefabs:load(source, scope.paths)
        end,
        instantiate = function(_, source, properties, parent)
            return prefabs:load(source, scope.paths):instantiate(properties, parent or scope.node)
        end,
    }

    return setmetatable(view, {
        __index = function(_, key)
            local value = world[key]
            if type(value) ~= 'function' then
                return value
            end
            -- Methods run on the real world whatever object they were called on.
            local wrapper = wrappers[key]
            if not wrapper then
                wrapper = function(_, ...)
                    return value(world, ...)
                end
                wrappers[key] = wrapper
            end
            return wrapper
        end,
        __newindex = function(_, key, value)
            world[key] = value
        end,
    })
end

return WorldView
