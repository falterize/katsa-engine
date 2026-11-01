local Physics = require('source.engine.physics')

local Tests = {}
Tests.__index = Tests

function Tests.new(manager)
    io.stdout:setvbuf('no')
    return setmetatable({}, Tests)
end

function Tests:update() end

function Tests:draw()
    if self.done then
        return
    end
    self.done = true
    local module = 'source.engine.physics.3d.backends.jolt.driver'
    assert(not package.loaded[module], 'Oimo startup loaded the Jolt driver')
    assert(
        not package.loaded['source.engine.physics.3d.backends.jolt.library'],
        'Oimo startup loaded a native library'
    )
    local world = Physics.new({ backend = 'oimo' })
    assert(world.backendName == 'oimo' and world.driver == nil)
    world:release()

    -- Emulate an unsupported platform at the loader boundary, without changing
    -- binaries, caches or the global native callback procedure table.
    local previous = package.preload[module]
    package.preload[module] = function()
        error('Selection fixture: Jolt unavailable')
    end
    local fallback = Physics.new({ backend = 'auto' })
    assert(fallback.backendName == 'oimo')
    assert(fallback.backendFallback:find('Selection fixture', 1, true))
    fallback:release()
    -- LuaJIT keeps a failed require sentinel; clear it before the strict retry.
    package.loaded[module] = nil
    local ok, message = pcall(Physics.new, { backend = 'jolt' })
    package.loaded[module], package.preload[module] = nil, previous
    assert(not ok and tostring(message):find('Jolt backend unavailable', 1, true))
    print('PASSED v104 backend selection: lazy Oimo, auto fallback, strict Jolt')
    katsa.event.quit()
end

return Tests
