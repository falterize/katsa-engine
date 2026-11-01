-- Capture immutable-for-this-pass camera inputs once, rather than per mesh.
local M = require('source.engine.math.math3d')

local Frustum = {}

function Frustum.capture(camera, state)
    state = state or {}
    local hx, hy = camera.width / (2 * camera.focal), camera.height / (2 * camera.focal)
    state.view, state.position = camera.view, camera.worldPosition or camera.position
    state.distanceSquared = camera.drawDistance ^ 2
    state.near, state.far = camera.near, camera.far
    state.hx, state.hy = hx, hy
    state.radiusX, state.radiusY = math.sqrt(1 + hx * hx), math.sqrt(1 + hy * hy)
    return state
end

function Frustum.visible(state, position, radius)
    local x, y, z = M.transform(state.view, position[1], position[2], position[3])
    if M.distanceSquared(position, state.position) > state.distanceSquared then
        return false
    end
    return z + radius >= state.near
        and z - radius <= state.far
        and math.abs(x) <= z * state.hx + radius * state.radiusX
        and math.abs(y) <= z * state.hy + radius * state.radiusY
end

return Frustum
