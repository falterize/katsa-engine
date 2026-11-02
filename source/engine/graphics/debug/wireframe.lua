local unpack = require('../../math.array').unpack
local ipairs = require('../../math.array').ipairs
local pairs = require('../../math.array').pairs
-- Explicit edge ribbons avoid derivative-dependent triangle-interior discard.
local Wireframe = {}
local format = {
    { 'VertexPosition', 'float', 3 },
    { 'edgeEnd', 'float', 3 },
    { 'edgeCorner', 'float', 2 },
}
local skinFormat = { unpack(format) }
skinFormat[4], skinFormat[5] = { 'skinJoints', 'float', 4 }, { 'skinWeights', 'float', 4 }
skinFormat[6], skinFormat[7] = { 'edgeJoints', 'float', 4 }, { 'edgeWeights', 'float', 4 }
local skinEightFormat = { unpack(skinFormat) }
skinEightFormat[8], skinEightFormat[9] =
    { 'skinJointsExtra', 'float', 4 }, { 'skinWeightsExtra', 'float', 4 }
skinEightFormat[10], skinEightFormat[11] =
    { 'edgeJointsExtra', 'float', 4 }, { 'edgeWeightsExtra', 'float', 4 }
local corners = { { 0, -1 }, { 1, -1 }, { 0, 1 }, { 1, 1 } }

function Wireframe.mesh(renderer, geometry)
    renderer.wireMeshes = renderer.wireMeshes or {}
    local cached, source = renderer.wireMeshes[geometry], geometry.mesh
    local first, drawLength = source:getDrawRange()
    first = first or 1
    if
        cached
        and cached.source == source
        and cached.revision == geometry.revision
        and cached.boundsRevision == geometry.boundsRevision
        and cached.first == first
        and cached.length == drawLength
        and cached.count == source:getVertexCount()
    then
        return cached.mesh
    end
    if cached then
        cached.mesh:release()
    end
    local map, vertices, edges, indices = source:getVertexMap(), {}, {}, {}
    local jointOffset, weightOffset, offset = nil, nil, 1
    local extraJointOffset, extraWeightOffset
    for _, attribute in ipairs(source:getVertexFormat()) do
        if attribute[1] == 'skinJoints' then
            jointOffset = offset
        end
        if attribute[1] == 'skinWeights' then
            weightOffset = offset
        end
        if geometry.eightWeights and attribute[1] == 'instanceRow1' then
            extraJointOffset = offset
        elseif geometry.eightWeights and attribute[1] == 'instanceRow2' then
            extraWeightOffset = offset
        end
        offset = offset + attribute[3]
    end

    local function edge(a, b)
        local key = math.min(a, b) .. ':' .. math.max(a, b)
        if edges[key] then
            return
        end
        edges[key] = true
        local va, vb = { source:getVertex(a) }, { source:getVertex(b) }
        local base = #vertices
        for _, index in ipairs({ 1, 2, 3, 3, 2, 4 }) do
            indices[#indices + 1] = base + index
        end
        for _, corner in ipairs(corners) do
            local row = { va[1], va[2], va[3], vb[1], vb[2], vb[3], corner[1], corner[2] }
            if jointOffset and weightOffset then
                for _, vertex in ipairs({ va, vb }) do
                    for i = 0, 3 do
                        row[#row + 1] = vertex[jointOffset + i]
                    end
                    for i = 0, 3 do
                        row[#row + 1] = vertex[weightOffset + i]
                    end
                end
            end
            if extraJointOffset and extraWeightOffset then
                for _, vertex in ipairs({ va, vb }) do
                    for i = 0, 3 do
                        row[#row + 1] = vertex[extraJointOffset + i]
                    end
                    for i = 0, 3 do
                        row[#row + 1] = vertex[extraWeightOffset + i]
                    end
                end
            end
            vertices[#vertices + 1] = row
        end
    end
    local count = map and #map or source:getVertexCount()
    local length = math.min(drawLength or math.huge, count - first + 1)

    local function index(i)
        return map and map[i] or i
    end
    local mode = source:getDrawMode()
    if mode == 'triangles' then
        for i = first, first + length - 3, 3 do
            local a, b, c = index(i), index(i + 1), index(i + 2)
            edge(a, b)
            edge(b, c)
            edge(c, a)
        end
    elseif mode == 'fan' or mode == 'strip' then
        for i = first + 2, first + length - 1 do
            local a, b, c = index(mode == 'fan' and first or i - 2), index(i - 1), index(i)
            edge(a, b)
            edge(b, c)
            edge(c, a)
        end
    end
    local mesh = katsa.graphics.newMesh(
        extraJointOffset and skinEightFormat
            or (jointOffset and weightOffset and skinFormat or format),
        #vertices > 0 and vertices or 1,
        'triangles',
        'static'
    )
    if #indices > 0 then
        mesh:setVertexMap(indices)
    end
    renderer.wireMeshes[geometry] = {
        mesh = mesh,
        source = source,
        revision = geometry.revision,
        boundsRevision = geometry.boundsRevision,
        count = source:getVertexCount(),
        first = first,
        length = drawLength,
    }
    return mesh
end

function Wireframe.draw(renderer, object)
    if object:isA('ParticleEmitter3D') then
        return
    end
    local g, shader = katsa.graphics, renderer.wireShader
    g.setShader(shader)
    if renderer.shaderFrames[shader] ~= renderer.frame then
        shader:send('viewProjection', 'row', renderer.camera.viewProjection)
        shader:send(
            'viewportSize',
            { renderer.width * renderer.density, renderer.height * renderer.density }
        )
        renderer.shaderFrames[shader] = renderer.frame
    end
    shader:send('model', 'row', object.canvas and object.matrix or object.combined or object.matrix)
    shader:send(
        'opacity',
        (object.color and object.color[4] or 1)
            * (object._renderOpacity or object:getEffectiveOpacity())
    )
    require('source.engine.animation.skeleton.skinning').bind(shader, object)
    local mesh = Wireframe.mesh(renderer, object.geometry or renderer.quad)
    g.setMeshCullMode('none')
    g.setColor(1, 1, 1, 1)
    renderer.stats.mainTriangles = renderer.stats.mainTriangles
        + require('source.engine.graphics.debug.triangles').mesh(mesh)
    g.draw(mesh)
end

function Wireframe.release(renderer)
    for _, cached in pairs(renderer.wireMeshes or {}) do
        cached.mesh:release()
    end
    renderer.wireMeshes = nil
end

return Wireframe
