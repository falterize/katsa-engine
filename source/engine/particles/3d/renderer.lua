local RenderRange = require('../../components.renderRange')
local Layering = require('../../components.layering')
local ipairs = require('../../math.array').ipairs
local M = require('../../math.math3d')

local R = {}
local format = {
    { 'VertexPosition', 'float', 3 },
    { 'VertexTexCoord', 'float', 2 },
    { 'VertexColor', 'float', 4 },
}
local corners = require('./basis').corners
local Sequence = require('../../animation.sequence')

local function sample(emitter, key, t, out)
    local ramp = emitter.lifetimeRamp
    return Sequence.evaluate(ramp.bindings[key], t, ramp.interpolation, out)
end

local function far(a, b)
    return a.depth > b.depth
end

function R.draw(system, camera, emitter)
    if
        emitter
        and not require('source.engine.particles.visibility').relevant(emitter, camera, true)
    then
        return
    end
    local g = katsa.graphics
    local start = katsa.timer.getTime()
    local stats = system.stats
    if #system.emitters == 0 then
        return
    end
    if not system.shader then
        system.shader = system.world.resources:own(
            g.newShader(
                require('source.engine.graphics.shaders.shaderSource').read(
                    'assets/shaders/particles/sprite.glsl'
                )
            )
        )
    end
    g.push('all')
    g.setShader(system.shader)
    system.shader:send('viewProjection', 'row', camera.viewProjection)
    g.setDepthMode('less', false)
    g.setMeshCullMode('none')
    g.setColor(1, 1, 1, 1)
    local world = system.world
    -- Emitters enter the same transparency list as other world renderables.
    system._drawList = system._drawList or {}
    system._drawList[1] = emitter
    local list = emitter and system._drawList or system.emitters
    for _, emitter in ipairs(list) do
        world:resolveLayerGroup(emitter)
        local material = require('source.engine.graphics.shaders.materialResolver').resolve(world, emitter)
        local shader = material and material.shader or system.shader
        g.setShader(shader)
        require('source.engine.particles.lighting').bind(shader, world, camera, emitter)
        shader:send('viewProjection', 'row', camera.viewProjection)
        if material then
            material:bind(world.simulationTime or 0)
        end
        local matrix = emitter:getRenderWorldMatrix()
        local order = emitter._renderOrder or {}
        emitter._renderOrder = order
        local n = 0
        if emitter:isVisible() and Layering.sees(camera, emitter) then
            for _, p in ipairs(emitter.particles) do
                local x, y, z = p.x, p.y, p.z
                if p.space == 'Local' then
                    x, y, z = M.transform(matrix, x, y, z)
                end
                p.boundPosition = p.boundPosition or {}
                p.boundPosition[1], p.boundPosition[2], p.boundPosition[3] = x, y, z
                local size = math.max(0, p.size * sample(emitter, 'size', p.age / p.life))
                local distance = (x - camera.worldPosition[1]) ^ 2
                    + (y - camera.worldPosition[2]) ^ 2
                    + (z - camera.worldPosition[3]) ^ 2
                if
                    RenderRange.within(emitter.maxDistance, distance, size)
                    and camera:visible(p.boundPosition, size)
                then
                    n = n + 1
                    order[n] = p
                    p.rx, p.ry, p.rz = x, y, z
                    p.renderSize = size
                    p.depth = (x - camera.worldPosition[1]) * camera.forward[1]
                        + (y - camera.worldPosition[2]) * camera.forward[2]
                        + (z - camera.worldPosition[3]) * camera.forward[3]
                end
            end
        end
        for i = #order, n + 1, -1 do
            order[i] = nil
        end
        if n > 0 then
            table.sort(order, far)
            local capacity = emitter._meshCapacity or 0
            if capacity < n then
                if emitter._particleMesh then
                    emitter._particleMesh:release()
                end
                capacity = math.max(16, capacity)
                while capacity < n do
                    capacity = capacity * 2
                end
                emitter._particleMesh = g.newMesh(format, capacity * 6, 'triangles', 'stream')
                emitter._meshCapacity = capacity
            end
            local vertices = emitter._vertices or {}
            emitter._vertices = vertices
            local image = require('source.engine.components.image').resolve(
                world.resources,
                emitter,
                emitter.texture,
                world.environment
            )
            emitter._particleMesh:setTexture(image)
            local index = 0
            for _, p in ipairs(order) do
                local t = math.min(1, p.age / p.life)
                p.renderColor = sample(emitter, 'color', t, p.renderColor)
                local red, green, blue = p.renderColor[1], p.renderColor[2], p.renderColor[3]
                local alpha = math.max(0, math.min(1, 1 - sample(emitter, 'transparency', t)))
                    * emitter:getEffectiveOpacity()
                local rx, ry, rz, ux, uy, uz =
                    require('source.engine.particles.basis').resolve(emitter, p, camera, matrix)
                local u0, v0, uw, vh =
                    require('source.engine.particles.image').uv(emitter, p, image, p.renderSize)
                local cos, sin =
                    math.cos(p.rotation + math.rad(sample(emitter, 'rotation', t))),
                    math.sin(p.rotation + math.rad(sample(emitter, 'rotation', t)))
                local half = p.renderSize * 0.5
                for _, corner in ipairs(corners) do
                    index = index + 1
                    local v = vertices[index] or {}
                    vertices[index] = v
                    local x, y =
                        (corner[1] * cos - corner[2] * sin) * half,
                        (corner[1] * sin + corner[2] * cos) * half
                    v[1], v[2], v[3] =
                        p.rx + rx * x + ux * y, p.ry + ry * x + uy * y, p.rz + rz * x + uz * y
                    v[4], v[5] = u0 + corner[3] * uw, v0 + corner[4] * vh
                    v[6], v[7], v[8], v[9] = red, green, blue, alpha
                end
            end
            emitter._particleMesh:setVertices(vertices, 1, n * 6)
            emitter._particleMesh:setDrawRange(1, n * 6)
            local blend = emitter.blendMode
            shader:send('multiplyMode', blend == 'Multiply')
            g.setBlendMode(
                blend == 'Add' and 'add' or blend == 'Multiply' and 'multiply' or 'alpha',
                blend == 'Multiply' and 'premultiplied' or 'alphamultiply'
            )
            g.draw(emitter._particleMesh)
            stats.drawCalls = stats.drawCalls + 1
            stats.rendered = stats.rendered + n
        end
    end
    -- The one-entry list is reused to avoid a table per draw; drop the emitter so a destroyed one
    -- (and its whole node tree) is not kept alive until the next particle draw.
    system._drawList[1] = nil
    g.pop()
    stats.drawMilliseconds = (stats.drawMilliseconds or 0) + (katsa.timer.getTime() - start) * 1000
end

return R
