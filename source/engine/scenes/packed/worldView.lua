local Node = require('source.engine.nodes')
local Resource = require('./resource')
local Build = require('./build')

-- The `scene.world` a prefab's scripts see: the world of the scene that holds the copy, with two
-- differences. `create` puts spatial nodes under the copy's own Node3D unless a parent is given
-- (UI and 2D nodes go into the copy's own World2D), and rewrites the prefab's resource names
-- (`scene://`, `./scene://`, `../scene://`, manifest aliases) so the world finds its assets.
-- `prefabs` resolves paths against the prefab's scene. Everything else is the real world.
local WorldView = {}

-- Where a node with no parent goes: spatial nodes under the copy's Node3D, UI and 2D nodes into
-- the copy's own World2D (made on first use), the world's own classes where they always go.
local function defaultParent(world, scope, className)
    local types = Node.getClass(className, world)._types
    if types.World2D or types.Environment then
        return nil
    elseif types.UINode then
        return scope.world2d().content
    elseif types.Node2D or types.Constraint2D then
        return scope.world2d()
    end
    return scope.node
end

-- world: the real world. scope: { node = the copy's Node3D, context = Resource context,
-- paths = the prefab scene's asset roots, world2d = function returning the copy's World2D }.
function WorldView.new(world, scope)
    local wrappers = {}
    local view = {}

    function view.create(_, className, properties, parent)
        parent = parent or defaultParent(world, scope, className)
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
