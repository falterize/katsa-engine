local ipairs = require('source.engine.math.array').ipairs
local pairs = require('source.engine.math.array').pairs
-- Optional early visibility for costly fully opaque built-in material batches.
local Opacity = require('source.engine.materials.opacity')
local Triangles = require('source.engine.graphics.debug.triangles')
local Skinning = require('source.engine.animation.skeleton.skinning')

local Prepass = {}
local Opaque = require('source.engine.materials.opaqueMesh')

local function eligible(object, renderer)
    return not object._shaderBoundsUnknown
        and not object.onTop
        and Opaque.eligible(object, renderer)
end

function Prepass.draw(renderer)
    renderer.depthPrepassActive = false
    renderer.stats.depthPrepassReused = false
    local stats = renderer.stats
    stats.depthPrepassMilliseconds, stats.depthPrepassTriangles, stats.depthPrepassDrawCalls =
        0, 0, 0
    if
        renderer.worldDebugWire
        or renderer.depthPrepass == false
        or renderer.actualMSAA > 0
        or renderer.lights.count < 4
        or #renderer.opaque < 64
    then
        return
    end
    local previous = renderer.prepassCamera or {}
    renderer.prepassCamera = previous
    local moved = false
    for i = 1, 16 do
        if previous[i] ~= renderer.camera.viewProjection[i] then
            moved = true
            previous[i] = renderer.camera.viewProjection[i]
        end
    end
    -- Driver waits on changed instance buffers outweighed pixel savings in this mode.
    if not moved and (stats.updatedMeshes or 0) > 0 then
        return
    end
    for _, object in ipairs(renderer.opaque) do
        if not eligible(object, renderer) then
            return
        end
    end
    local start, g = love.timer.getTime(), love.graphics
    local width, height = renderer.canvas:getPixelDimensions()
    if width * height * 16 > renderer.maxRenderBytes then
        return
    end
    local depth = renderer.prepassDepth
    if not depth or depth:getPixelWidth() ~= width or depth:getPixelHeight() ~= height then
        if depth then
            depth:release()
        end
        renderer.prepassDepth = g.newCanvas(
            renderer.width,
            renderer.height,
            { format = 'depth24', readable = true, dpiscale = renderer.density }
        )
        depth = renderer.prepassDepth
        depth:setFilter('nearest', 'nearest')
    end
    local dependencies = renderer._frameCache
    local cache = renderer.prepassCache
    local reusable = dependencies
        and dependencies.meshSnapshots
        and (not dependencies.volatile or dependencies.meshesStable)
    if
        reusable
        and cache
        and cache.owner == dependencies
        and cache.revision == dependencies.casterRevision
        and cache.depth == depth
        and not moved
    then
        renderer.depthPrepassActive = true
        stats.depthPrepassReused = true
        return
    end
    local shader = renderer.prepassShader
    if not shader then
        shader = renderer.resources:own(
            g.newShader(
                require('source.engine.graphics.shaderSource').read(
                    'assets/shaders/engine/depthPrepass.glsl'
                )
            )
        )
        renderer.prepassShader = shader
    end
    g.push('all')
    g.setCanvas({ depthstencil = depth })
    g.clear(0, 0, 0, 0, 0, 1)
    g.setColorMask(false, false, false, false)
    g.setDepthMode('less', true)
    g.setShader(shader)
    shader:send('viewProjection', 'row', renderer.camera.viewProjection)
    shader:send('instanced', true)
    renderer.batches.drawing = true
    for _, group in ipairs(renderer.batches.groups) do
        if group.count > 0 then
            Skinning.bind(shader, group.example)
            local object = group.example
            local mesh
            if object.geometry.eightWeights then
                assert(group.count == 1, 'Extended skins require individual depth draws')
                shader:send('instanced', false)
                shader:send('model', 'row', object.combined or object.matrix)
                mesh = object.geometry.mesh
            else
                shader:send('instanced', true)
                mesh = renderer.batches:upload(group)
            end
            g.setMeshCullMode(group.example.doubleSided and 'none' or 'back')
            if object.geometry.eightWeights then
                g.draw(mesh)
            else
                g.drawInstanced(mesh, group.count)
            end
            stats.depthPrepassDrawCalls = stats.depthPrepassDrawCalls + 1
            stats.depthPrepassTriangles = stats.depthPrepassTriangles
                + Triangles.mesh(mesh) * group.count
        end
    end
    renderer.batches.drawing = false
    for mesh in pairs(renderer.batches.attached) do
        renderer.batches:detach(mesh)
        renderer.batches.attached[mesh] = nil
    end
    g.pop()
    renderer.depthPrepassActive = true
    if reusable then
        renderer.prepassCache =
            { owner = dependencies, revision = dependencies.casterRevision, depth = depth }
    else
        renderer.prepassCache = nil
    end
    stats.depthPrepassMilliseconds = (love.timer.getTime() - start) * 1000
end

function Prepass.release(renderer)
    renderer.prepassCache = nil
    if renderer.prepassDepth then
        renderer.prepassDepth:release()
        renderer.prepassDepth = nil
    end
end

return Prepass
