local unpack = require('../../math.array').unpack

-- Runtime blend shapes (Blender "Shape Keys", Godot "Blend Shapes") for imported meshes.
--
-- A glTF mesh owns one set of weights that drives every draw of that mesh, so the state is shared
-- by the Mesh3D objects of one model node. Each object gets its own dynamic copy of the vertex
-- data; the imported asset stays untouched and can be instanced again. Values are written
-- immediately but the vertices are rebuilt once per frame (World3D flushes the queue after the
-- node update), however many shapes changed.
local BlendShapes = {}
BlendShapes.__index = BlendShapes

local EPSILON = 1e-6

-- `shared` = { names, defaults, count } of the glTF mesh.
function BlendShapes.new(world, shared)
    local values = {}
    for t = 1, shared.count do
        values[t] = shared.defaults[t]
    end
    return setmetatable({
        world = world,
        names = shared.names,
        defaults = shared.defaults,
        values = values,
        count = shared.count,
        draws = {},
        dirty = true,
    }, BlendShapes)
end

-- Gives `object` a private dynamic copy of the imported geometry and links it to the state.
function BlendShapes.attach(state, object, morph)
    local Geometry = require('source.engine.graphics.geometry.primitives')
    local source = object.geometry
    local rows = {}
    for i, row in ipairs(source.vertices) do
        rows[i] = { unpack(row) }
    end
    -- Rows longer than the static layout (8 numbers) carry skin joints and weights.
    local geometry = Geometry.mesh(rows, #rows[1] > 8, 'dynamic')
    geometry.revision = 0
    state.world.resources:own(geometry.mesh)
    object.geometry = geometry
    object.blendShapes = state
    state.draws[#state.draws + 1] = { object = object, geometry = geometry, morph = morph, rows = rows }
    state.dirty = true
    state:queue()
end

function BlendShapes:queue()
    local queue = self.world.blendShapeQueue
    if not queue then
        queue = {}
        self.world.blendShapeQueue = queue
    end
    if not self.queued then
        self.queued = true
        queue[#queue + 1] = self
    end
end

-- Resolves a 1-based index or a shape name. Returns nil for an unknown shape.
function BlendShapes:resolve(shape)
    if type(shape) == 'number' then
        return shape >= 1 and shape <= self.count and shape == math.floor(shape) and shape or nil
    end
    for t, name in ipairs(self.names) do
        if name == shape then
            return t
        end
    end
end

function BlendShapes:set(shape, value)
    local index = assert(self:resolve(shape), 'Unknown blend shape: ' .. tostring(shape))
    assert(type(value) == 'number' and value == value, 'Blend shape value must be a number')
    if self.values[index] ~= value then
        self.values[index] = value
        self.dirty = true
        self:queue()
    end
end

function BlendShapes:setAll(list)
    for t = 1, self.count do
        if list[t] ~= nil then
            self:set(t, list[t])
        end
    end
end

-- Rebuilds the vertices of every draw from the base data plus the weighted deltas.
function BlendShapes:flush()
    self.queued = false
    if not self.dirty then
        return
    end
    self.dirty = false
    local active = {}
    for t = 1, self.count do
        if math.abs(self.values[t]) > EPSILON then
            active[#active + 1] = t
        end
    end
    for _, draw in ipairs(self.draws) do
        -- Skin limits may swap the object's geometry; keep updating only the one we own.
        if draw.object.geometry == draw.geometry and not draw.object.destroyed then
            local morph, rows = draw.morph, draw.rows
            local basePosition, baseNormal = morph.basePosition, morph.baseNormal
            local radius = 0
            for i = 1, morph.n do
                local at = i * 3 - 3
                local x, y, z = basePosition[at], basePosition[at + 1], basePosition[at + 2]
                local nx, ny, nz = baseNormal[at], baseNormal[at + 1], baseNormal[at + 2]
                local shaped = false
                for _, t in ipairs(active) do
                    local w = self.values[t]
                    local p, n = morph.positions[t], morph.normals[t]
                    x, y, z = x + w * p[at], y + w * p[at + 1], z + w * p[at + 2]
                    if n then
                        nx, ny, nz = nx + w * n[at], ny + w * n[at + 1], nz + w * n[at + 2]
                        shaped = true
                    end
                end
                if shaped then
                    local length = math.sqrt(nx * nx + ny * ny + nz * nz)
                    if length > EPSILON then
                        nx, ny, nz = nx / length, ny / length, nz / length
                    end
                end
                radius = math.max(radius, x * x + y * y + z * z)
                local row = rows[i]
                row[1], row[2], row[3] = x, y, z
                row[6], row[7], row[8] = nx, ny, nz
            end
            draw.geometry.mesh:setVertices(rows)
            draw.geometry.revision = draw.geometry.revision + 1
            draw.geometry.radius = math.sqrt(radius) -- culling follows the morphed extent
            draw.object._batchRevision = (draw.object._batchRevision or 0) + 1
        end
    end
end

-- Flushes the states changed since the last call (World3D calls this once per node update).
function BlendShapes.flushQueue(world)
    local queue = world.blendShapeQueue
    if not queue or #queue == 0 then
        return
    end
    world.blendShapeQueue = {}
    for _, state in ipairs(queue) do
        state:flush()
    end
end

return BlendShapes
