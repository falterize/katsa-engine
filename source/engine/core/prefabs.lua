-- Scene-owned factories; gameplay behavior stays outside the engine.
local Prefabs = {}
Prefabs.__index = Prefabs

function Prefabs.new(world)
    return setmetatable({ world = world, factories = {} }, Prefabs)
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

return Prefabs
