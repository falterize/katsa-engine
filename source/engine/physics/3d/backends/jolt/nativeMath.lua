local ffi = require('ffi')

local NativeMath = {}

-- Engine Dynamic/Static/Kinematic -> Jolt Dynamic/Static/Kinematic.
NativeMath.motion = { [0] = 2, [1] = 0, [2] = 1 }

function NativeMath.cast(kind, pointer)
    return ffi.cast('JPH_' .. kind .. '*', pointer)
end

function NativeMath.vector(out, value, scale)
    scale = scale or 1
    out.x = (value.x or value[1]) * scale
    out.y = (value.y or value[2]) * scale
    out.z = (value.z or value[3]) * scale
    return out
end

function NativeMath.quaternion(out, matrix, scratch)
    scratch:fromMat3(matrix)
    out.x, out.y, out.z, out.w = scratch.x, scratch.y, scratch.z, scratch.w
    return out
end

return NativeMath
