-- Selection is per Physics instance. Explicit requests never silently fall back.
local Oimo = require('source.engine.physics.3d.backends.oimo.driver')

local Registry = { default = os.getenv('KATSA_PHYSICS_BACKEND') or 'auto' }
local names = { auto = true, oimo = true, jolt = true }

function Registry.setDefault(name)
    assert(names[name], 'Unknown physics backend: ' .. tostring(name))
    Registry.default = name
end

function Registry.resolve(name)
    name = name or Registry.default
    assert(names[name], 'Unknown physics backend: ' .. tostring(name))
    if name == 'oimo' then
        return 'oimo', Oimo
    end
    local ok, adapter = pcall(require, 'source.engine.physics.3d.backends.jolt.driver')
    if ok then
        return 'jolt', adapter
    end
    if name == 'jolt' then
        error('Jolt backend unavailable: ' .. tostring(adapter), 0)
    end
    return 'oimo', Oimo, tostring(adapter)
end

return Registry
