-- The selection outline: twelve thin bars around a unit cube, placed over the primary selected
-- node every frame. One mesh, no per-frame allocation except the transform tables.
local Assign = require('../core.assign')
local Geometry = require('source.engine.graphics.geometry.primitives')

local SelectionBox = {}
SelectionBox.__index = SelectionBox

-- Bars slightly larger than the cube so they never z-fight its faces.
local function geometry()
    local vertices = {}
    local lo, hi, t = -0.505, 0.505, 0.014
    local function box(x0, y0, z0, x1, y1, z1)
        local c = {
            { x0, y0, z0 }, { x1, y0, z0 }, { x1, y1, z0 }, { x0, y1, z0 },
            { x0, y0, z1 }, { x1, y0, z1 }, { x1, y1, z1 }, { x0, y1, z1 },
        }
        local quads = {
            { 1, 2, 3, 4, 0, 0, -1 }, { 6, 5, 8, 7, 0, 0, 1 }, { 5, 1, 4, 8, -1, 0, 0 },
            { 2, 6, 7, 3, 1, 0, 0 }, { 4, 3, 7, 8, 0, 1, 0 }, { 5, 6, 2, 1, 0, -1, 0 },
        }
        for _, q in ipairs(quads) do
            local a, b, cc, d = c[q[1]], c[q[2]], c[q[3]], c[q[4]]
            for _, p in ipairs({ a, b, cc, a, cc, d }) do
                vertices[#vertices + 1] = { p[1], p[2], p[3], 0, 0, q[5], q[6], q[7] }
            end
        end
    end
    for _, y in ipairs({ lo, hi - t }) do
        for _, z in ipairs({ lo, hi - t }) do
            box(lo, y, z, hi, y + t, z + t)
        end
    end
    for _, x in ipairs({ lo, hi - t }) do
        for _, z in ipairs({ lo, hi - t }) do
            box(x, lo, z, x + t, hi, z + t)
        end
    end
    for _, x in ipairs({ lo, hi - t }) do
        for _, y in ipairs({ lo, hi - t }) do
            box(x, y, lo, x + t, y + t, hi)
        end
    end
    return Geometry.mesh(vertices)
end

-- `index` makes the node name unique: object names must be unique in a world.
function SelectionBox.new(world, parent, index)
    local self = setmetatable({}, SelectionBox)
    self.node = world:create('Mesh3D', {
        name = 'EditorSelection' .. (index or 1),
        geometry = geometry(),
        color = { 1, 0.62, 0.1, 1 },
        lightInfluence = 0,
        canQuery = false,
        castShadow = false,
        visible = false,
    }, parent)
    world:create('Shader3D', { name = 'OnTop', shaderPath = 'editor://shaders/onTop.glsl' }, self.node)
    return self
end

-- Follows `target` (a Mesh3D with position, rotation and size) or hides when it is nil.
function SelectionBox:follow(target)
    local node = self.node
    -- Only nodes with a transform get an outline (groups, lights and the like may lack one).
    if not target or target.destroyed or not target.position or not target.rotation then
        if node.visible then
            node.visible = false
        end
        return
    end
    local p, r, size = target.position, target.rotation, target.size or { 1, 1, 1 }
    Assign.vec(node, 'position', p[1], p[2], p[3])
    Assign.vec(node, 'rotation', r[1], r[2], r[3])
    Assign.vec(node, 'size', size[1], size[2], size[3])
    if not node.visible then
        node.visible = true
    end
end

local PRIMARY, OTHER = { 1, 0.62, 0.1, 1 }, { 1, 0.9, 0.45, 1 }

function SelectionBox:setPrimary(primary)
    if self.primary ~= primary then
        self.primary = primary
        self.node.color = primary and PRIMARY or OTHER
    end
end

function SelectionBox:release()
    if self.node and not self.node.destroyed then
        self.node:destroy()
    end
end

return SelectionBox
