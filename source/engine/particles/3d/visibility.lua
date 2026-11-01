local ipairs = require('source.engine.math.array').ipairs
-- Test existing particles as well as the source: world-space trails can outlive an offscreen
-- emitter.
local M = require('source.engine.math.math3d')
local bit = require('bit')

local V = {}

function V.point(emitter, camera, x, y, z, radius)
    if not camera then
        return false
    end
    local position = emitter._visibilityPosition or {}
    emitter._visibilityPosition = position
    position[1], position[2], position[3] = x, y, z
    return (
        emitter.maxDistance <= 0
        or M.distanceSquared(position, camera.worldPosition or camera.position)
            <= (emitter.maxDistance + radius) ^ 2
    ) and camera:visible(position, radius)
end

function V.relevant(emitter, camera, renderPose)
    if
        not camera
        or not emitter:isVisible()
        or emitter:getEffectiveOpacity() <= 0
        or bit.band(emitter.layers or 1, camera.layers or -1) == 0
    then
        return false
    end
    local matrix = renderPose and emitter:getRenderWorldMatrix() or emitter:getWorldMatrix()
    local scale = math.sqrt(
        matrix[1] ^ 2
            + matrix[2] ^ 2
            + matrix[3] ^ 2
            + matrix[5] ^ 2
            + matrix[6] ^ 2
            + matrix[7] ^ 2
            + matrix[9] ^ 2
            + matrix[10] ^ 2
            + matrix[11] ^ 2
    )
    local shape = emitter.shapeSize
    local radius = math.sqrt(shape[1] ^ 2 + shape[2] ^ 2 + shape[3] ^ 2) * scale * 0.5
        + emitter.startSize[2]
    if
        emitter.rate > 0
        and emitter.enabled ~= false
        and V.point(emitter, camera, matrix[4], matrix[8], matrix[12], radius)
    then
        return true
    end
    for _, particle in ipairs(emitter.particles) do
        local x, y, z = particle.x, particle.y, particle.z
        if particle.space == 'Local' then
            x, y, z = M.transform(matrix, x, y, z)
        end
        local size = require('source.engine.animation.sequence').evaluate(
            emitter.lifetimeRamp.bindings.size,
            particle.age / particle.life,
            emitter.lifetimeRamp.interpolation
        )
        if V.point(emitter, camera, x, y, z, math.max(0, particle.size * size)) then
            return true
        end
    end
    return false
end

return V
