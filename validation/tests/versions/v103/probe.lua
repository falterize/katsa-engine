local T = {}
T.__index = T

function T.new(manager)
    return setmetatable({}, T)
end

function T:update() end

function T:draw()
    if self.done then
        return
    end
    self.done = true
    local lib = require('source.engine.physics.3d.backends.jolt.library')
    print('JOLT FFI LOADED', lib.platform, lib.hash, lib.ffi.sizeof('JPH_PhysicsSystemSettings'))
    katsa.event.quit()
end

return T
