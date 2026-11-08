local ipairs = require('source.engine.math.array').ipairs
local Math = require('source.engine.math.math3d')
local Level = require('source.engine.physics.3d.collisionLevel')
local ModelCollider = {}

function ModelCollider.install(Physics, Body3D)
    function Physics.modelCollider(object, level)
        local kind = Level.kind(level or 'Bounding Box')
        if kind == 'box' then
            local min, max =
                { math.huge, math.huge, math.huge }, { -math.huge, -math.huge, -math.huge }
            for _, v in ipairs(object.geometry.vertices) do
                for i = 1, 3 do
                    local x = v[i] * object.size[i]
                    min[i] = math.min(min[i], x)
                    max[i] = math.max(max[i], x)
                end
            end
            local size, position = {}, {}
            for i = 1, 3 do
                size[i] = math.max(0.02, max[i] - min[i])
                position[i] = (max[i] + min[i]) * 0.5
            end
            return { shape = 'Box', size = size, position = position }
        end
        local points, seen = {}, {}
        for _, v in ipairs(object.geometry.vertices) do
            local key = string.format('%.6f:%.6f:%.6f', v[1], v[2], v[3])
            if not seen[key] then
                seen[key] = true
                points[#points + 1] =
                    { v[1] * object.size[1], v[2] * object.size[2], v[3] * object.size[3] }
            end
        end
        if kind == 'convex' then
            return { shape = 'Convex', vertices = points }
        end
        -- Simplified and Multiple Convex are built by the collider builder (modelCollider.lua).
        assert(kind == 'trimesh', 'Physics.modelCollider builds Bounding Box, Single Convex and Trimesh')
        local children = {}
        local vertices = object.geometry.vertices
        -- Static surface collision: one thin convex triangular prism per render triangle.
        for i = 1, #vertices, 3 do
            local a, b, c = vertices[i], vertices[i + 1], vertices[i + 2]
            local nx, ny, nz = Math.normalize(
                (b[2] - a[2]) * (c[3] - a[3]) - (b[3] - a[3]) * (c[2] - a[2]),
                (b[3] - a[3]) * (c[1] - a[1]) - (b[1] - a[1]) * (c[3] - a[3]),
                (b[1] - a[1]) * (c[2] - a[2]) - (b[2] - a[2]) * (c[1] - a[1])
            )
            local prism = {}
            for _, v in ipairs({ a, b, c }) do
                prism[#prism + 1] = {
                    v[1] * object.size[1] + nx * 0.03,
                    v[2] * object.size[2] + ny * 0.03,
                    v[3] * object.size[3] + nz * 0.03,
                }
                prism[#prism + 1] = {
                    v[1] * object.size[1] - nx * 0.03,
                    v[2] * object.size[2] - ny * 0.03,
                    v[3] * object.size[3] - nz * 0.03,
                }
            end
            children[#children + 1] = { shape = 'Convex', vertices = prism }
        end
        return { shape = 'Compound', children = children }
    end
end

return ModelCollider
