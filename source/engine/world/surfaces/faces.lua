local unpack = require('../../math.array').unpack
-- Quad normals face local -Z. Front is the parent's local -Z bounding-box face.
local Math = require('../../math.math3d')
local Affine = require('../../math.affine')
local Bounds = require('../../graphics.geometry.objectBounds')

local Faces = {}
local definitions = {
    Front = { 1, 1, 2, 1, 3, -1 },
    Back = { 1, -1, 2, 1, 3, 1 },
    Left = { 3, -1, 2, 1, 1, -1 },
    Right = { 3, 1, 2, 1, 1, 1 },
    Top = { 1, 1, 3, 1, 2, 1 },
    Bottom = { 1, 1, 3, -1, 2, -1 },
}

function Faces.validate(face)
    assert(definitions[face], 'face must be Front/Back/Left/Right/Top/Bottom')
end

function Faces.referenceSize(node)
    local face = assert(definitions[node.face], 'Invalid surface face')
    local parent = require('source.engine.world.surfaces.support').resolve(node)
    if parent and parent:isA('Mesh3D') then
        Bounds.get(parent)
        local b = parent.geometry.bounds
        return (b[face[1] + 3] - b[face[1]]) * parent.size[face[1]],
            (b[face[3] + 3] - b[face[3]]) * parent.size[face[3]]
    end
    local dimensions = node.supportSize or { 1, 1, 1 }
    return dimensions[face[1]], dimensions[face[3]]
end

function Faces.update(node, camera)
    local parent = require('source.engine.world.surfaces.support').resolve(node)
    if not parent or not parent.getWorldMatrix then
        node.drawable = false
        return
    end
    local face = assert(definitions[node.face], 'face must be Front/Back/Left/Right/Top/Bottom')
    local u, us, v, vs, n, ns = unpack(face)
    local center = { 0, 0, 0 }
    local dimensions = { 0, 0, 0 }
    if parent:isA('Mesh3D') then
        Bounds.get(parent)
        local bounds = parent.geometry.bounds
        for i = 1, 3 do
            dimensions[i] = (bounds[i + 3] - bounds[i]) * parent.size[i]
            center[i] = (bounds[i] + bounds[i + 3]) * 0.5 * parent.size[i]
        end
        center[n] = (ns > 0 and bounds[n + 3] or bounds[n]) * parent.size[n]
    else
        dimensions = node.supportSize or { 1, 1, 1 }
        center[n] = ns * dimensions[n] * 0.5
    end
    center[n] = center[n]
        + ns * (node.surfaceOffset or 0.03)
        + math.max(-32, math.min(32, node.zIndex or 0)) * ns * 0.0001
    local width, height
    if node.size and #node.size == 4 then
        width, height = require('source.engine.ui.layout.metrics').resolve(
            node.size,
            dimensions[u],
            dimensions[v],
            node.sizeRelativeTo or node.relativeTo
        )
    elseif node.surfaceSize then
        width, height = node.surfaceSize[1], node.surfaceSize[2]
    else
        width, height = dimensions[u], dimensions[v]
    end
    assert(width > 0 and height > 0, 'Surface dimensions must be positive')
    local faceMatrix = node._faceMatrix or Math.identity()
    node._faceMatrix = faceMatrix
    for i = 1, 12 do
        faceMatrix[i] = 0
    end
    faceMatrix[(u - 1) * 4 + 1] = us
    faceMatrix[(v - 1) * 4 + 2] = vs
    faceMatrix[(n - 1) * 4 + 3] = -ns
    for i = 1, 3 do
        faceMatrix[(i - 1) * 4 + 4] = center[i]
    end
    if node.position and #node.position == 4 then
        local x, y = require('source.engine.ui.layout.metrics').resolve(
            node.position,
            dimensions[u],
            dimensions[v],
            node.positionRelativeTo or node.relativeTo
        )
        local anchor = node.anchorPoint or { 0.5, 0.5 }
        faceMatrix[(u - 1) * 4 + 4] = faceMatrix[(u - 1) * 4 + 4]
            + us * (x - dimensions[u] * 0.5 + (0.5 - anchor[1]) * width)
        faceMatrix[(v - 1) * 4 + 4] = faceMatrix[(v - 1) * 4 + 4]
            - vs * (y - dimensions[v] * 0.5 + (0.5 - anchor[2]) * height)
    end
    node._surfaceLocal = Math.multiply(faceMatrix, node:getLocalMatrix(), node._surfaceLocal)
    node.matrix = Math.multiply(
        require('source.engine.world.surfaces.support').frame(node, parent, true),
        node._surfaceLocal,
        node.matrix
    )
    for i = 0, 2 do
        node.matrix[i * 4 + 1] = node.matrix[i * 4 + 1] * width
        node.matrix[i * 4 + 2] = node.matrix[i * 4 + 2] * height
    end
    node.worldPosition = node.worldPosition or {}
    local m = node.matrix
    node.worldPosition[1], node.worldPosition[2], node.worldPosition[3] = m[4], m[8], m[12]
    Math.normalMatrix(m, node.normal)
    local _, _, depth = camera:project(node.worldPosition)
    node.depth = depth or math.huge
    local inv = Affine.inverse(m, node._surfaceInverse)
    node._surfaceInverse = inv
    local cp = camera.worldPosition or camera.position
    local _, _, z = Math.transform(inv, unpack(cp))
    local frontFacing = z < 0
    if camera.orthographic then
        -- Parallel projection has no eye point; the surface faces the camera when the shared
        -- view direction enters its front side.
        local f = camera.forward
        frontFacing = inv[9] * f[1] + inv[10] * f[2] + inv[11] * f[3] > 0
    end
    node.drawable = node:isVisible()
        and node.transparency < 1
        and depth ~= nil
        and (node.doubleSided or frontFacing)
        and (
            node.maxDistance <= 0
            or Math.distanceSquared(cp, node.worldPosition) <= node.maxDistance ^ 2
        )
    node.worldWidth = math.sqrt(m[1] ^ 2 + m[5] ^ 2 + m[9] ^ 2)
    node.worldHeight = math.sqrt(m[2] ^ 2 + m[6] ^ 2 + m[10] ^ 2)
    node.radius = math.sqrt(node.worldWidth ^ 2 + node.worldHeight ^ 2) * 0.5
    local pixels = camera:pixelsPerUnitAt(math.max(0.001, node.depth))
    node.screenWidth, node.screenHeight = node.worldWidth * pixels, node.worldHeight * pixels
end

function Faces.point(node, camera, x, y)
    if not node._surfaceInverse then
        return
    end
    local origin, ray = camera:screenRay(x, y)
    local wx, wy, wz = ray[1], ray[2], ray[3]
    local inv = node._surfaceInverse
    local ox, oy, oz = Math.transform(inv, origin[1], origin[2], origin[3])
    local vx, vy, vz =
        inv[1] * wx + inv[2] * wy + inv[3] * wz,
        inv[5] * wx + inv[6] * wy + inv[7] * wz,
        inv[9] * wx + inv[10] * wy + inv[11] * wz
    if math.abs(vz) < 1e-8 or (not node.doubleSided and vz <= 0) then
        return
    end
    local t = -oz / vz
    if t <= 0 then
        return
    end
    local c = node.resolvedCanvasSize or node.canvasSize
    return (ox + vx * t + 0.5) * c[1], (0.5 - oy - vy * t) * c[2], t
end

return Faces
