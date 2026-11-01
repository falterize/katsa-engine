local ipairs = require('source.engine.math.array').ipairs
-- Counts submitted primitives, not fragments surviving depth/culling tests.
local Triangles = {}
local cache = setmetatable({}, { __mode = 'k' })
local epoch = 0

function Triangles.begin()
    epoch = epoch + 1
end

function Triangles.mesh(mesh)
    local record = cache[mesh]
    if record and record.epoch == epoch then
        return record.count
    end
    local map = mesh:getVertexMap()
    local first, length = mesh:getDrawRange()
    first = first or 1
    local count = math.max(
        0,
        math.min(length or math.huge, (map and #map or mesh:getVertexCount()) - first + 1)
    )
    local mode = mesh:getDrawMode()
    if mode == 'triangles' then
        count = math.floor(count / 3)
    elseif mode == 'strip' or mode == 'fan' then
        count = math.max(0, count - 2)
    else
        count = 0
    end
    record = record or {}
    record.epoch, record.count = epoch, count
    cache[mesh] = record
    return count
end

function Triangles.list(objects, meshes)
    local count = 0
    for _, object in ipairs(objects) do
        if object:isA('Mesh3D') then
            count = count + Triangles.mesh(meshes and meshes[object] or object.geometry.mesh)
        end
    end
    return count
end

return Triangles
