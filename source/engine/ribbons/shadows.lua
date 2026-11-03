-- Shadow proxies for ribbons: one alpha-tested mesh per node in the shared shadow atlas, the same
-- mechanism as particle shadows (ParticleEmitter3D). The proxy also lets a ribbon receive shadows.
local M = require('../math.math3d')
local Geometry = require('./geometry')
local Renderer = require('./renderer')
local Image = require('../components.image')

local S = {}

local format = {
    { 'VertexPosition', 'float', 3 },
    { 'VertexTexCoord', 'float', 2 },
    { 'vertexNormal', 'float', 3 },
    { 'VertexColor', 'float', 4 },
}

local function newProxy(node)
    local proxy = {
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
        isA = function()
            return false
        end,
        isVisible = function()
            return not node.destroyed and node.castShadow and node:isVisible()
        end,
        getEffectiveOpacity = function()
            return node:getEffectiveOpacity()
        end,
    }
    node:onDestroy(function()
        proxy.destroyed = true
        if proxy.geometry.mesh then
            proxy.geometry.mesh:release()
            proxy.geometry.mesh = nil
        end
    end)
    return proxy
end

local function release(proxy)
    if proxy and proxy.geometry.mesh then
        proxy.geometry.mesh:release()
        proxy.geometry.mesh = nil
        proxy.capacity = 0
    end
end

-- Appends one proxy per casting / receiving ribbon to `output` (already holding the world objects).
function S.prepare(world, camera, output)
    if not world.environment.shadows.enabled then
        return output
    end
    local time = world.simulationTime or 0
    for _, node in ipairs(world.ribbons.nodes) do
        local proxy = node._shadowProxy
        local count = 0
        if (node.castShadow or node.receiveShadow) and (node._count or 0) >= 2 then
            if not proxy then
                proxy = newProxy(node)
                node._shadowProxy = proxy
            end
            proxy._resolvedMaterial = require('source.engine.shaders.materialResolver').resolve(world, node)
            proxy._shaderBoundsUnknown = node._shaderBoundsUnknown
            proxy._shaderBoundsPadding = node._shaderBoundsPadding
            local image = Image.resolve(world.resources, node, node.texture, world.environment)
            local options = Renderer.options(node, camera, node._shadowOptions)
            node._shadowOptions = options
            Renderer.mapping(node, image, time, options)
            Renderer.applyStatic(node._points, node._count, options)
            local flat = node._shadowFlat or {}
            node._shadowFlat = flat
            local n = Geometry.strip(node._points, node._count, options, flat)
            local vertices = proxy.geometry.vertices
            local visibleAlpha = 0
            for i = 1, n do
                local source = flat[i]
                local v = vertices[i] or {}
                vertices[i] = v
                v[1], v[2], v[3], v[4], v[5] = source[1], source[2], source[3], source[4], source[5]
                v[6], v[7], v[8] = 0, 1, 0
                v[9], v[10], v[11], v[12] = 1, 1, 1, source[9]
                visibleAlpha = math.max(visibleAlpha, source[9])
            end
            for i = #vertices, n + 1, -1 do
                vertices[i] = nil
            end
            count = visibleAlpha > node.shadowAlphaCutoff and n or 0
            if count > 0 then
                if not proxy.geometry.mesh or proxy.capacity < count then
                    release(proxy)
                    proxy.geometry.mesh = katsa.graphics.newMesh(format, vertices, 'triangles', 'stream')
                    proxy.capacity = count
                else
                    proxy.geometry.mesh:setVertices(vertices, 1, count)
                end
                proxy.geometry.mesh:setDrawRange(1, count)
                proxy.geometry.boundsRevision = (proxy.geometry.boundsRevision or 0) + 1
                proxy.shadowRevision = (proxy.shadowRevision or 0) + 1
                proxy.castShadow = node.castShadow
                proxy.receiveShadow = node.receiveShadow
                proxy.layers = node.layers
                proxy.shadowLayers = node.shadowLayers
                proxy.shadowGroup = node.shadowGroup
                proxy.image = image
                proxy.alphaCutoff = node.shadowAlphaCutoff
                proxy._renderOpacity = node:getEffectiveOpacity()
                local center = node._center
                proxy.worldPosition[1], proxy.worldPosition[2], proxy.worldPosition[3] =
                    center[1], center[2], center[3]
                proxy.radius = node._radius
                output[#output + 1] = proxy
            end
        end
        if count == 0 then
            release(proxy)
        end
    end
    return output
end

return S
