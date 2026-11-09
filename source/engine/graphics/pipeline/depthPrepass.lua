local ipairs = require('../../math.array').ipairs
local pairs = require('../../math.array').pairs
-- Optional early visibility for costly fully opaque built-in material batches.
local Opacity = require('../materials.opacity')
local Triangles = require('../debug.triangles')
local Skinning = require('../../animation.skeleton.skinning')

local Prepass = {}
local Opaque = require('../materials.opaqueMesh')

local function eligible(object, renderer)
    return not object._shaderBoundsUnknown
        and not object.onTop
        and Opaque.eligible(object, renderer)
end

local function depthShader(renderer)
    local shader = renderer.prepassShader
    if not shader then
        shader = renderer.resources:own(
            katsa.graphics.newShader(
                require('source.engine.graphics.shaders.shaderSource').read(
                    'assets/shaders/engine/depthPrepass.glsl'
                )
            )
        )
        renderer.prepassShader = shader
    end
    return shader
end

-- Draws every batched opaque group into `depth` (depth only). `onlyEligible` skips groups the
-- early pass could not reproduce exactly (alpha cutouts, custom shaders).
local function drawGroups(renderer, shader, depth, stats, onlyEligible)
    local g = katsa.graphics
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
        if group.count > 0 and (not onlyEligible or eligible(group.example, renderer)) then
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
    local start, g = katsa.timer.getTime(), katsa.graphics
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
    local shader = depthShader(renderer)
    drawGroups(renderer, shader, depth, stats)
    renderer.depthPrepassActive = true
    if reusable then
        renderer.prepassCache =
            { owner = dependencies, revision = dependencies.casterRevision, depth = depth }
    else
        renderer.prepassCache = nil
    end
    stats.depthPrepassMilliseconds = (katsa.timer.getTime() - start) * 1000
end

-- Readable depth of the batched opaque scene for post-processing, drawn on demand (the early
-- pass is optional and skips MSAA targets). Unlike the early pass it covers every opaque group. The canvas is kept for the renderer's lifetime.
function Prepass.renderSceneDepth(renderer)
    local g = katsa.graphics
    local width, height = renderer.canvas:getPixelDimensions()
    local depth = renderer.postDepth
    if not depth or depth:getPixelWidth() ~= width or depth:getPixelHeight() ~= height then
        if depth then
            depth:release()
        end
        depth = g.newCanvas(
            renderer.width,
            renderer.height,
            { format = 'depth24', readable = true, dpiscale = renderer.density }
        )
        depth:setFilter('nearest', 'nearest')
        renderer.postDepth = depth
    end
    renderer.postDepthStats = renderer.postDepthStats
        or { depthPrepassDrawCalls = 0, depthPrepassTriangles = 0 }
    -- Every opaque group, including custom materials and cutouts: depth-only drawing cannot copy
    -- their vertex code or alpha test, but a close depth is far better than none (SSAO, DOF and fog
    -- would treat those objects as sky).
    drawGroups(renderer, depthShader(renderer), depth, renderer.postDepthStats, false)
    return depth
end

function Prepass.release(renderer)
    if renderer.postDepth then
        renderer.postDepth:release()
        renderer.postDepth = nil
    end
    renderer.prepassCache = nil
    if renderer.prepassDepth then
        renderer.prepassDepth:release()
        renderer.prepassDepth = nil
    end
end

return Prepass
