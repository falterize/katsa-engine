local ipairs = require('source.engine.math.array').ipairs

local System = {}
local names = { 'lighting', 'shadows', 'fog', 'toneMapping' }

function System.resolve(world, object, nodes)
    object._systemEffects = object._systemEffects or {}
    local effects = object._systemEffects
    for _, name in ipairs(names) do
        effects[name] = true
        local layer = world.environment.systemLayers[name]
        for _, upper in ipairs(nodes) do
            if world.shaderLayers:suppresses(upper.shaderLayer, layer) then
                effects[name] = false
                break
            end
        end
    end
end

function System.bind(shader, object)
    local effects = object and object._systemEffects
    for _, name in ipairs({ 'fog', 'toneMapping' }) do
        local uniform = name == 'fog' and 'systemFogEnabled' or 'systemToneMappingEnabled'
        if shader:hasUniform(uniform) then
            shader:send(uniform, not effects or effects[name] ~= false)
        end
    end
end

return System
