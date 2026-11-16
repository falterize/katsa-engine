-- A system of the prefab scene: one instance per copy, updated with it.
local Counter = {}
Counter.__index = Counter

function Counter.create(state, scene)
    return setmetatable({ state = state, scene = scene }, Counter)
end

function Counter:update(dt)
    self.scene.node:setAttribute('Ticks', (self.scene.node:getAttribute('Ticks') or 0) + 1)
end

return Counter
