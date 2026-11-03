-- Shadow proxy shared by every node that builds its own geometry each frame (particle emitters,
-- ribbons). The proxy is a small object in the shadow caster list that owns one stream mesh; the
-- shadow pass then treats it like any other alpha tested caster, and a receiving node also lists it
-- as a receiver. One module, so the two producers cannot drift apart.
local M = require('../../math.math3d')

local CasterProxy = {}

local format = {
    { 'VertexPosition', 'float', 3 },
    { 'VertexTexCoord', 'float', 2 },
    { 'vertexNormal', 'float', 3 },
    { 'VertexColor', 'float', 4 },
}

local function create(node)
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
        lightInfluence = 0,
        enabled = true,
        capacity = 0,
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
        CasterProxy.release(proxy)
    end)
    return proxy
end

-- Returns the node's proxy (created on first use) with its shader-layer material refreshed.
function CasterProxy.begin(world, node)
    local proxy = node._shadowProxy
    if not proxy then
        proxy = create(node)
        node._shadowProxy = proxy
    end
    proxy._resolvedMaterial = require('source.engine.shaders.materialResolver').resolve(world, node)
    proxy._shaderBoundsUnknown = node._shaderBoundsUnknown
    proxy._shaderBoundsPadding = node._shaderBoundsPadding
    return proxy
end

-- Writes vertex `index` of the proxy geometry (up-facing normal, white, `alpha`).
function CasterProxy.write(proxy, index, x, y, z, u, v, alpha)
    local vertices = proxy.geometry.vertices
    local vertex = vertices[index] or {}
    vertices[index] = vertex
    vertex[1], vertex[2], vertex[3], vertex[4], vertex[5] = x, y, z, u, v
    vertex[6], vertex[7], vertex[8] = 0, 1, 0
    vertex[9], vertex[10], vertex[11], vertex[12] = 1, 1, 1, alpha
end

-- Uploads the first `count` vertices and publishes the node's shadow settings on the proxy.
-- `bounds` is { cx, cy, cz, radius }; returns true when the proxy was added to `output`.
function CasterProxy.publish(proxy, node, count, image, bounds, output)
    local vertices = proxy.geometry.vertices
    for i = #vertices, count + 1, -1 do
        vertices[i] = nil
    end
    if count == 0 then
        CasterProxy.release(proxy)
        return false
    end
    local geometry = proxy.geometry
    if not geometry.mesh or proxy.capacity < count then
        CasterProxy.release(proxy)
        geometry.mesh = katsa.graphics.newMesh(format, vertices, 'triangles', 'stream')
        proxy.capacity = count
    else
        geometry.mesh:setVertices(vertices, 1, count)
    end
    geometry.mesh:setDrawRange(1, count)
    geometry.boundsRevision = (geometry.boundsRevision or 0) + 1
    proxy.shadowRevision = (proxy.shadowRevision or 0) + 1
    proxy.castShadow, proxy.receiveShadow = node.castShadow, node.receiveShadow
    proxy.layers, proxy.shadowLayers, proxy.shadowGroup =
        node.layers, node.shadowLayers, node.shadowGroup
    proxy.image, proxy.alphaCutoff = image, node.shadowAlphaCutoff
    proxy._renderOpacity = node:getEffectiveOpacity()
    proxy.worldPosition[1], proxy.worldPosition[2], proxy.worldPosition[3] =
        bounds[1], bounds[2], bounds[3]
    proxy.radius = bounds[4]
    output[#output + 1] = proxy
    return true
end

function CasterProxy.release(proxy)
    local mesh = proxy and proxy.geometry.mesh
    if mesh then
        mesh:release()
        proxy.geometry.mesh = nil
        proxy.capacity = 0
    end
end

return CasterProxy
