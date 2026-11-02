local unpack = require('../math.array').unpack
local ipairs = require('../math.array').ipairs
local pairs = require('../math.array').pairs
-- Reusable, bounded material-map composition avoids exceeding mobile sampler limits.
local B = {}

function B.releaseBuffers(object)
    local cache = object._surfaceBlendCache
    if not cache then
        return
    end
    for key, canvas in pairs(cache.canvases) do
        canvas:release()
        cache.canvases[key] = nil
    end
    if cache.scratch then
        cache.scratch:release()
        cache.scratch = nil
    end
    cache.size, cache.count = nil, nil
    for _, key in ipairs({
        'colorMap',
        'normalMap',
        'roughnessMap',
        'metalnessMap',
        'occlusionMap',
        'emissionMap',
    }) do
        cache.result[key] = ''
    end
end
local keys =
    { 'colorMap', 'normalMap', 'roughnessMap', 'metalnessMap', 'occlusionMap', 'emissionMap' }
local scalars = {
    'transparency',
    'colorMap',
    'normalMap',
    'roughnessMap',
    'metalnessMap',
    'occlusionMap',
    'emissionMap',
    'roughness',
    'metalness',
    'normalScale',
    'occlusionStrength',
    'emissionStrength',
    'alphaMode',
    'alphaCutoff',
    'pixelate',
    'imageMode',
    'xml',
    'fitMode',
    'atlasFrame',
}
local vectors = {
    'color',
    'emissionColor',
    'atlasGrid',
    'textureSize',
    'textureOffset',
    'tileSize',
    'tileOffset',
}

local function changed(cache, nodes)
    local dirty = cache.count ~= #nodes
    cache.count = #nodes
    for i, node in ipairs(nodes) do
        local snapshot = cache.snapshots[i] or {}
        cache.snapshots[i] = snapshot
        if snapshot.node ~= node then
            dirty = true
            snapshot.node = node
        end
        for _, key in ipairs(scalars) do
            if snapshot[key] ~= node[key] then
                dirty = true
                snapshot[key] = node[key]
            end
        end
        for _, key in ipairs(vectors) do
            local v = snapshot[key] or {}
            snapshot[key] = v
            for j = 1, #node[key] do
                if v[j] ~= node[key][j] then
                    dirty = true
                    v[j] = node[key][j]
                end
            end
        end
    end
    return dirty
end

function B.resolve(world, object, nodes)
    local cache = object._surfaceBlendCache
    if not cache then
        cache = {
            snapshots = {},
            canvases = {},
            factor = {},
            result = {
                color = { 1, 1, 1 },
                roughness = 1,
                metalness = 1,
                normalScale = 1,
                occlusionStrength = 1,
                emissionColor = { 1, 1, 1 },
                emissionStrength = 1,
                pixelate = false,
                alphaMode = 'Inherit',
                alphaCutoff = 0,
                _composed = true,
            },
        }
        object._surfaceBlendCache = cache
        -- These buffers belong to the mesh, not to the shared immutable asset cache.
        object:onDestroy(function()
            for _, canvas in pairs(cache.canvases) do
                canvas:release()
            end
            if cache.scratch then
                cache.scratch:release()
            end
        end)
    end
    local requested = math.min(
        512,
        math.max(32, math.floor(world.environment.render.surfaceBlendResolution or 256))
    )
    local resized = cache.size ~= requested
        or cache.parentX ~= object.size[1]
        or cache.parentY ~= object.size[2]
    cache.parentX, cache.parentY = object.size[1], object.size[2]
    if not changed(cache, nodes) and not resized then
        return cache.result
    end
    local Surface = require('source.engine.materials.surface')
    local g = katsa.graphics
    cache.shader = cache.shader
        or world.resources:cached('shader', 'surfaceBlend', function(owner)
            return owner:own(g.newShader('assets/shaders/engine/surfaceBlend.glsl'))
        end)
    local size = math.min(
        512,
        math.max(32, math.floor(world.environment.render.surfaceBlendResolution or 256))
    )
    if cache.size ~= size then
        for _, canvas in pairs(cache.canvases) do
            canvas:release()
        end
        cache.canvases = {}
        if cache.scratch then
            cache.scratch:release()
            cache.scratch = nil
        end
        cache.size = size
    end
    local total = 0
    for _, node in ipairs(nodes) do
        total = total + 1 - node.transparency
    end
    local baseWeight = math.max(0, 1 - total)
    total = math.max(1, total)
    cache.result.roughness = baseWeight
    cache.result.metalness = 0
    local emission = cache.result.emissionColor
    emission[1], emission[2], emission[3] = 0, 0, 0
    for _, node in ipairs(nodes) do
        local weight = (1 - node.transparency) / total
        cache.result.roughness = cache.result.roughness + node.roughness * weight
        cache.result.metalness = cache.result.metalness + node.metalness * weight
        for i = 1, 3 do
            emission[i] = emission[i] + node.emissionColor[i] * node.emissionStrength * weight
        end
    end
    cache.result.pixelate = true
    for _, node in ipairs(nodes) do
        if not node.pixelate then
            cache.result.pixelate = false
        end
    end
    cache.result._missing = false
    cache.result.alphaMode = 'Inherit'
    cache.result.alphaCutoff = 0
    for _, node in ipairs(nodes) do
        if node.alphaMode == 'Blend' then
            cache.result.alphaMode = 'Blend'
        end
        if node.alphaMode == 'Mask' then
            cache.result.alphaCutoff = math.max(cache.result.alphaCutoff, node.alphaCutoff)
        end
    end
    if cache.result.alphaCutoff > 0 and cache.result.alphaMode ~= 'Blend' then
        cache.result.alphaMode = 'Mask'
    end
    g.push('all')
    g.origin()
    g.setScissor()
    g.setStencilTest()
    g.setDepthMode()
    g.setWireframe(false)
    g.setMeshCullMode('none')
    g.setColorMask(true, true, true, true)
    -- LÃ–VE's Add blend mode preserves destination alpha. Ping-pong RGBA instead.
    g.setBlendMode('replace', 'premultiplied')
    g.setColor(1, 1, 1, 1)
    g.setShader(cache.shader)
    for channel, key in ipairs(keys) do
        local needed = channel == 1
        for _, node in ipairs(nodes) do
            if node[key] ~= '' then
                needed = true
            end
        end
        if needed then
            if channel == 3 then
                cache.result.roughness = 1
            end
            if channel == 4 then
                cache.result.metalness = 1
            end
            if channel == 6 then
                emission[1], emission[2], emission[3] = 1, 1, 1
            end
            local format = g.getCanvasFormats().rgba16f and 'rgba16f' or 'rgba8'
            local canvas = cache.canvases[channel] or g.newCanvas(size, size, { format = format })
            cache.scratch = cache.scratch or g.newCanvas(size, size, { format = format })
            cache.canvases[channel] = canvas
            canvas:setFilter(
                cache.result.pixelate and 'nearest' or 'linear',
                cache.result.pixelate and 'nearest' or 'linear'
            )
            canvas:setWrap('repeat', 'repeat')
            cache.result[key] = canvas
            g.setCanvas(canvas)
            if channel == 2 then
                g.clear(0.5 * baseWeight, 0.5 * baseWeight, baseWeight, baseWeight)
            elseif channel == 4 or channel == 6 then
                g.clear(0, 0, 0, baseWeight)
            else
                g.clear(baseWeight, baseWeight, baseWeight, baseWeight)
            end
            for _, node in ipairs(nodes) do
                local source = Surface.image(world.resources, node, key, world.environment)
                if
                    type(node[key]) == 'string'
                    and node[key] ~= ''
                    and world.resources:isMissingImage(node[key])
                then
                    cache.result._missing = true
                end
                source = source or world.resources:image('white')
                local f = cache.factor
                f[1], f[2], f[3], f[4] = 1, 1, 1, 1
                if channel == 1 then
                    f[1], f[2], f[3] = unpack(node.color)
                elseif channel == 2 then
                    f[1] = node.normalScale
                elseif channel == 3 then
                    f[1] = node.roughness
                elseif channel == 4 then
                    f[1] = node.metalness
                elseif channel == 5 then
                    f[1] = node.occlusionStrength
                else
                    f[1], f[2], f[3] = unpack(node.emissionColor)
                    f[4] = node.emissionStrength
                end
                -- Flat normal for a material without a normal map.
                local noNormal = channel == 2 and node.normalMap == ''
                cache.shader:send('channel', noNormal and 0 or channel - 1)
                if noNormal then
                    f[1], f[2], f[3], f[4] = 0.5, 0.5, 1, 1
                end
                cache.shader:send('factor', f)
                cache.shader:send('weight', (1 - node.transparency) / total)
                cache.shader:send('opaque', node.alphaMode == 'Opaque')
                cache.shader:send('accumulatedMap', canvas)
                g.setCanvas(cache.scratch)
                require('source.engine.components.image').bindUV(cache.shader, node, source)
                local w, h = source:getDimensions()
                g.draw(source, 0, 0, 0, size / w, size / h)
                canvas, cache.scratch = cache.scratch, canvas
            end
            canvas:setFilter(
                cache.result.pixelate and 'nearest' or 'linear',
                cache.result.pixelate and 'nearest' or 'linear'
            )
            canvas:setWrap('repeat', 'repeat')
            cache.canvases[channel], cache.result[key] = canvas, canvas
        else
            if cache.canvases[channel] then
                cache.canvases[channel]:release()
                cache.canvases[channel] = nil
            end
            cache.result[key] = ''
        end
    end
    if cache.result.alphaMode ~= 'Inherit' or object.blend or (object.alphaCutoff or 0) > 0 then
        object._surfaceBlendRevision = (object._surfaceBlendRevision or 0) + 1
    end
    g.pop()
    require('source.engine.graphics.state').reapplyScissor()
    return cache.result
end

return B
