local ipairs = require('source.engine.math.array').ipairs
-- Bounded alpha-tested sprite geometry shares the ordinary shadow atlas.
local M = require('source.engine.math.math3d')
local Sequence = require('source.engine.animation.sequence')

local S = {}
local corners = {
    { -1, -1, 0, 1 },
    { 1, -1, 1, 1 },
    { 1, 1, 1, 0 },
    { -1, -1, 0, 1 },
    { 1, 1, 1, 0 },
    {
        -1,
        1,
        0,
        0,
    },
}
local format = {
    { 'VertexPosition', 'float', 3 },
    { 'VertexTexCoord', 'float', 2 },
    { 'vertexNormal', 'float', 3 },
    { 'VertexColor', 'float', 4 },
}

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
        if
            (emitter.castShadow or emitter.receiveShadow)
            and emitter:isVisible()
            and #emitter.particles > 0
            and emitter:getEffectiveOpacity() > 0
        then
            if not proxy then
                proxy = {
                    _particleCaster = true,
                    geometry = { vertices = {} },
                    matrix = M.identity(),
                    normal = { 1, 0, 0, 0, 1, 0, 0, 0, 1 },
                    color = { 1, 1, 1 },
                    size = { 1, 1, 1 },
                    worldPosition = { 0, 0, 0 },
                    doubleSided = true,
                    castShadow = true,
                    unlit = true,
                    enabled = true,
                }
                proxy.isA = function()
                    return false
                end
                proxy.isVisible = function()
                    return not emitter.destroyed and emitter.castShadow and emitter:isVisible()
                end
                proxy.getEffectiveOpacity = function()
                    return emitter:getEffectiveOpacity()
                end
                emitter._shadowProxy = proxy
                emitter:onDestroy(function()
                    proxy.destroyed = true
                    if proxy.geometry.mesh then
                        proxy.geometry.mesh:release()
                        proxy.geometry.mesh = nil
                    end
                end)
            end
            proxy._resolvedMaterial =
                require('source.engine.shaders.materialResolver').resolve(world, emitter)
            proxy._shaderBoundsUnknown = emitter._shaderBoundsUnknown
            proxy._shaderBoundsPadding = emitter._shaderBoundsPadding
            local matrix = emitter:getRenderWorldMatrix()
            local vertices = proxy.geometry.vertices
            local count = 0
            local min = { math.huge, math.huge, math.huge }
            local max = { -math.huge, -math.huge, -math.huge }
            for i = 1, math.min(#emitter.particles, emitter.shadowMaxParticles) do
                local p = emitter.particles[i]
                local t = p.age / p.life
                local alpha = 1
                    - Sequence.evaluate(
                        emitter.lifetimeRamp.bindings.transparency,
                        t,
                        emitter.lifetimeRamp.interpolation
                    )
                local half = p.size
                    * Sequence.evaluate(
                        emitter.lifetimeRamp.bindings.size,
                        t,
                        emitter.lifetimeRamp.interpolation
                    )
                    * 0.5
                local x, y, z = p.x, p.y, p.z
                if p.space == 'Local' then
                    x, y, z = M.transform(matrix, x, y, z)
                end
                if half > 0 and alpha > emitter.shadowAlphaCutoff then
                    local image = require('source.engine.components.image').resolve(
                        world.resources,
                        emitter,
                        emitter.texture
                    )
                    local u0, v0, uw, vh =
                        require('source.engine.particles.image').uv(emitter, p, image, half * 2)
                    local bx, by, bz, upx, upy, upz =
                        require('source.engine.particles.basis').resolve(emitter, p, camera, matrix)
                    local rotation = p.rotation
                        + math.rad(
                            Sequence.evaluate(
                                emitter.lifetimeRamp.bindings.rotation,
                                t,
                                emitter.lifetimeRamp.interpolation
                            )
                        )
                    for _, corner in ipairs(corners) do
                        count = count + 1
                        local v = vertices[count] or {}
                        vertices[count] = v
                        local rx = (corner[1] * math.cos(rotation) - corner[2] * math.sin(rotation))
                            * half
                        local uy = (corner[1] * math.sin(rotation) + corner[2] * math.cos(rotation))
                            * half
                        v[1], v[2], v[3] =
                            x + bx * rx + upx * uy, y + by * rx + upy * uy, z + bz * rx + upz * uy
                        v[4], v[5] = u0 + corner[3] * uw, v0 + corner[4] * vh
                        v[6], v[7], v[8] = 0, 1, 0
                        v[9], v[10], v[11], v[12] = 1, 1, 1, alpha
                        for axis = 1, 3 do
                            min[axis] = math.min(min[axis], v[axis])
                            max[axis] = math.max(max[axis], v[axis])
                        end
                    end
                end
            end
            for i = #vertices, count + 1, -1 do
                vertices[i] = nil
            end
            if count > 0 then
                if not proxy.geometry.mesh or proxy.capacity < count then
                    if proxy.geometry.mesh then
                        proxy.geometry.mesh:release()
                    end
                    proxy.geometry.mesh =
                        katsa.graphics.newMesh(format, vertices, 'triangles', 'stream')
                    proxy.capacity = count
                else
                    proxy.geometry.mesh:setVertices(vertices, 1, count)
                end
                proxy.geometry.mesh:setDrawRange(1, count)
                proxy.geometry.boundsRevision = (proxy.geometry.boundsRevision or 0) + 1
                proxy.shadowRevision = (proxy.shadowRevision or 0) + 1
                proxy.castShadow = emitter.castShadow
                proxy.receiveShadow = emitter.receiveShadow
                proxy.layers = emitter.layers
                proxy.shadowLayers = emitter.shadowLayers
                proxy.shadowGroup = emitter.shadowGroup
                proxy.image = require('source.engine.components.image').resolve(
                    world.resources,
                    emitter,
                    emitter.texture,
                    world.environment
                )
                proxy.alphaCutoff = emitter.shadowAlphaCutoff
                proxy._renderOpacity = emitter:getEffectiveOpacity()
                local radius = 0
                for axis = 1, 3 do
                    proxy.worldPosition[axis] = (min[axis] + max[axis]) * 0.5
                    radius = radius + (max[axis] - min[axis]) ^ 2
                end
                proxy.radius = math.sqrt(radius) * 0.5
                output[#output + 1] = proxy
            end
        elseif proxy and proxy.geometry.mesh then
            proxy.geometry.mesh:release()
            proxy.geometry.mesh = nil
            proxy.capacity = 0
        end
    end
    return output
end

return S
