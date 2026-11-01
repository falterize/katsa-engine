local unpack = require('source.engine.math.array').unpack
local ipairs = require('source.engine.math.array').ipairs
local pairs = require('source.engine.math.array').pairs
-- Optional build-time sidecar. Source hashing prevents stale geometry from loading.
local JSON = require('vendor.json')
local Geometry = require('source.engine.graphics.geometry.primitives')
local M = require('source.engine.math.math3d')

local Packed = {}

function Packed.write(model, source, destination)
    local header = {
        nodes = {},
        roots = model.roots,
        skins = model.skins,
        animations = {},
        parts = {},
        sourceHash = katsa.data.hash('sha256', assert(katsa.filesystem.read(source))),
    }
    header.sourceHash = katsa.data.encode('string', 'hex', header.sourceHash)
    for i, n in ipairs(model.nodes) do
        header.nodes[i] = {
            name = n.name,
            translation = n.rest.translation,
            rotation = n.rest.rotation,
            scale = n.rest.scale,
            matrix = n.matrix,
            children = n.children,
            mesh = n.mesh,
            skin = n.skin,
            isBone = n.isBone,
        }
    end
    for i, clip in ipairs(model.animations) do
        local c =
            { name = clip.name, duration = clip.duration, markers = clip.markers, channels = {} }
        for j, channel in ipairs(clip.channels) do
            c.channels[j] = {
                node = channel.node.index,
                target = channel.target,
                times = channel.times,
                values = channel.values,
                method = channel.method,
            }
        end
        header.animations[i] = c
    end
    local payload, offset = {}, 0
    for i, part in ipairs(model.parts) do
        assert(
            not part.material.image,
            'Packed sidecar builder currently requires external/baked material maps without '
                .. 'embedded image handles'
        )
        local vertices = part.geometry.vertices
        local vertexFloats = part.geometry.eightWeights and 24 or (part.palette and 16 or 8)
        local format = '< ' .. string.rep('f', vertexFloats)
        local rows, envelopes = {}, {}
        for j, v in ipairs(vertices) do
            rows[j] = katsa.data.pack('string', format, unpack(v))
            if part.palette then
                for k = 1, part.geometry.eightWeights and 8 or 4 do
                    local influenceOffset = k > 4 and 4 or 0
                    if v[12 + k + influenceOffset] > 0 then
                        local joint = part.palette[v[8 + k + influenceOffset] + 1] + 1
                        local bind = model.skins[part.skin + 1].inverseBindMatrices[joint]
                        local x, y, z = M.transform(bind, v[1], v[2], v[3])
                        envelopes[tostring(joint)] = math.max(
                            envelopes[tostring(joint)] or 0,
                            math.sqrt(x * x + y * y + z * z)
                        )
                    end
                end
            end
        end
        local bytes = table.concat(rows)
        payload[i] = bytes
        header.parts[i] = {
            name = part.name,
            node = part.node and part.node.index,
            skin = part.skin,
            palette = part.palette,
            material = part.material,
            radius = part.geometry.radius,
            count = #vertices,
            vertexFloats = vertexFloats,
            offset = offset,
            length = #bytes,
            envelopes = envelopes,
        }
        offset = offset + #bytes
    end
    local data = JSON.encode(header)
    local file = assert(io.open(destination, 'wb'))
    file:write('KMC1', katsa.data.pack('string', '<I4', #data), data, table.concat(payload))
    file:close()
end

function Packed.try(path, resources)
    local cachePath = path .. '.kmesh'
    if not katsa.filesystem.getInfo(cachePath) then
        return
    end
    local raw = assert(katsa.filesystem.read(cachePath))
    assert(raw:sub(1, 4) == 'KMC1', 'Invalid model sidecar magic')
    local length = katsa.data.unpack('<I4', raw, 5)
    local header = JSON.decode(raw:sub(9, 8 + length))
    local hash = katsa.data.encode(
        'string',
        'hex',
        katsa.data.hash('sha256', assert(katsa.filesystem.read(path)))
    )
    if hash ~= header.sourceHash then
        return
    end
    local model = {
        nodes = header.nodes,
        roots = header.roots,
        skins = header.skins or {},
        animations = header.animations,
        parts = {},
        loop = true,
        time = 0,
        packed = true,
    }
    for _, n in ipairs(model.nodes) do
        n.world = M.identity()
    end

    local function parent(index, owner)
        local n = model.nodes[index + 1]
        n.parent = owner
        for _, child in ipairs(n.children) do
            parent(child, n)
        end
    end
    for _, index in ipairs(model.roots) do
        parent(index, nil)
    end
    for _, clip in ipairs(model.animations) do
        for _, channel in ipairs(clip.channels) do
            channel.node = model.nodes[channel.node]
        end
    end
    for i, part in ipairs(header.parts) do
        local vertexFloats = part.vertexFloats or (part.palette and 16 or 8)
        assert(
            vertexFloats == (part.palette and 16 or 8) or part.palette and vertexFloats == 24,
            'Invalid packed vertex format'
        )
        local bytes = raw:sub(9 + length + part.offset, 8 + length + part.offset + part.length)
        assert(
            #bytes == part.length and part.length == part.count * vertexFloats * 4,
            'Truncated packed mesh data'
        )
        local mesh = resources:own(
            katsa.graphics.newMesh(
                vertexFloats == 24 and Geometry.skinEightFormat
                    or (part.palette and Geometry.skinFormat or Geometry.format),
                part.count,
                'triangles',
                'static'
            )
        )
        local data = katsa.data.newByteData(bytes)
        mesh:setVertices(data)
        data:release()
        local envelopes = {}
        for key, value in pairs(part.envelopes) do
            envelopes[tonumber(key)] = value
        end
        local geometry = {
            mesh = mesh,
            radius = part.radius,
            eightWeights = vertexFloats == 24,
            _assetGeometry = true,
            _bytes = bytes,
            _skinEnvelopes = part.palette and envelopes,
        }
        setmetatable(geometry, {
            __index = function(g, key)
                if key ~= 'vertices' then
                    return
                end
                local vertices = {}
                local count = vertexFloats
                for j = 1, part.count do
                    local v = {
                        katsa.data.unpack(
                            '<' .. string.rep('f', count),
                            bytes,
                            (j - 1) * count * 4 + 1
                        ),
                    }
                    v[#v] = nil
                    vertices[j] = v
                end
                rawset(g, 'vertices', vertices)
                return vertices
            end,
        })
        model.parts[i] = {
            name = part.name,
            geometry = geometry,
            palette = part.palette,
            skin = part.skin,
            material = part.material,
            node = part.node and model.nodes[part.node],
        }
    end
    require('source.engine.animation.skeleton.rig').initialize(model)
    model:update(0)
    return model
end

return Packed
