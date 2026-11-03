-- The car's own up axis in world space for the model's heading, nose-up pitch and right-side-up
-- roll (the same frame orientation.lua and PhysicsCar:readState use). Offsets measured "below the
-- chassis" must follow this axis, not world Y, or a tilted model drifts off its collision box.
local CarAxes = {}

function CarAxes.up(heading, pitch, roll, out)
    local h, p, r = math.rad(heading), math.rad(pitch), math.rad(roll)
    local sinH, cosH = math.sin(h), math.cos(h)
    local sinP, cosP = math.sin(p), math.cos(p)
    local sinR, cosR = math.sin(r), math.cos(r)
    -- Level right axis and the up axis after pitch; roll then turns them about the forward axis.
    local rightX, rightZ = cosH, -sinH
    local upX, upY, upZ = -sinH * sinP, cosP, -cosH * sinP
    out = out or {}
    out[1] = upX * cosR - rightX * sinR
    out[2] = upY * cosR
    out[3] = upZ * cosR - rightZ * sinR
    return out
end

return CarAxes
