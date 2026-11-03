local ipairs = require('../../math.array').ipairs
-- Bounded alpha-tested sprite geometry shares the ordinary shadow atlas.
local M = require('../../math.math3d')
local Sequence = require('../../animation.sequence')
local CasterProxy = require('../../graphics.shadows.casterProxy')
local Image = require('../../components.image')

local S = {}
local bounds = { 0, 0, 0, 0 }
local corners = require('./basis').corners
function S.prepare(world, camera, output)
    output = output or {}
    for i = #output, 1, -1 do
        output[i] = nil
    end
    for _, object in ipairs(world.objects) do
        output[#output + 1] = object
    end
    if not world.environment.shadows.enabled then
        return output
    end
    for _, emitter in ipairs(world.particles.emitters) do
        local proxy = emitter._shadowProxy
        local count = 0
        if
            (emitter.castShadow or emitter.receiveShadow)
            and emitter:isVisible()
            and #emitter.particles > 0
            and emitter:getEffectiveOpacity() > 0
        then
            proxy = CasterProxy.begin(world, emitter)
            local matrix = emitter:getRenderWorldMatrix()
            local min = { math.huge, math.huge, math.huge }
            local max = { -math.huge, -math.huge, -math.huge }
            local ramp = emitter.lifetimeRamp
            local image = Image.resolve(world.resources, emitter, emitter.texture, world.environment)
            for i = 1, math.min(#emitter.particles, emitter.shadowMaxParticles) do
                local p = emitter.particles[i]
                local t = p.age / p.life
                local alpha = 1 - Sequence.evaluate(ramp.bindings.transparency, t, ramp.interpolation)
                local half = p.size * Sequence.evaluate(ramp.bindings.size, t, ramp.interpolation) * 0.5
                local x, y, z = p.x, p.y, p.z
                if p.space == 'Local' then
                    x, y, z = M.transform(matrix, x, y, z)
                end
                if half > 0 and alpha > emitter.shadowAlphaCutoff then
                    local u0, v0, uw, vh =
                        require('source.engine.particles.image').uv(emitter, p, image, half * 2)
                    local bx, by, bz, upx, upy, upz =
                        require('source.engine.particles.basis').resolve(emitter, p, camera, matrix)
                    local rotation = p.rotation
                        + math.rad(Sequence.evaluate(ramp.bindings.rotation, t, ramp.interpolation))
                    local cos, sin = math.cos(rotation), math.sin(rotation)
                    for _, corner in ipairs(corners) do
                        count = count + 1
                        local rx = (corner[1] * cos - corner[2] * sin) * half
                        local uy = (corner[1] * sin + corner[2] * cos) * half
                        local vx, vy, vz =
                            x + bx * rx + upx * uy, y + by * rx + upy * uy, z + bz * rx + upz * uy
                        CasterProxy.write(
                            proxy,
                            count,
                            vx,
                            vy,
                            vz,
                            u0 + corner[3] * uw,
                            v0 + corner[4] * vh,
                            alpha
                        )
                        min[1], max[1] = math.min(min[1], vx), math.max(max[1], vx)
                        min[2], max[2] = math.min(min[2], vy), math.max(max[2], vy)
                        min[3], max[3] = math.min(min[3], vz), math.max(max[3], vz)
                    end
                end
            end
            if count > 0 then
                local dx, dy, dz = max[1] - min[1], max[2] - min[2], max[3] - min[3]
                bounds[1], bounds[2], bounds[3] =
                    (min[1] + max[1]) * 0.5, (min[2] + max[2]) * 0.5, (min[3] + max[3]) * 0.5
                bounds[4] = math.sqrt(dx * dx + dy * dy + dz * dz) * 0.5
            end
            CasterProxy.publish(proxy, emitter, count, image, bounds, output)
        elseif proxy then
            CasterProxy.release(proxy)
        end
    end
    return output
end

return S
