local Library = require('source.engine.physics.3d.backends.jolt.library')
local Jobs = require('source.engine.physics.3d.backends.jolt.native.jobs')

local State = {}

-- Epoch advances after the native step barrier; immediate setters invalidate their body.
function State.read(world, raw)
    if not Jobs.C or not raw._joltPtr then
        return
    end
    if raw._joltReadEpoch ~= world.poseEpoch then
        raw._joltReadState = raw._joltReadState or Library.ffi.new('KP_State')
        Jobs.C.KP_ReadBody(raw._joltPtr, raw._joltReadState)
        raw._joltReadEpoch = world.poseEpoch
    end
    return raw._joltReadState
end

function State.invalidate(raw)
    raw._joltReadEpoch = nil
    raw._joltMirrorEpoch = nil
end

return State
