-- The selection outline: twelve thin bars around a unit cube, placed over the primary selected
-- node every frame. One mesh, no per-frame allocation except the transform tables.
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

function SelectionBox.new(world, parent)
    local self = setmetatable({}, SelectionBox)
    self.node = world:create('Mesh3D', {
        name = 'EditorSelection',
        geometry = geometry(),
        color = { 1, 0.62, 0.1, 1 },
        lightInfluence = 0,
        canQuery = false,
        castShadow = false,
        visible = false,
    }, parent)
    world:create('Shader3D', { name = 'OnTop', shaderPath = 'scene://shaders/onTop.glsl' }, self.node)
    return self
end

-- Follows `target` (a Mesh3D with position, rotation and size) or hides when it is nil.
function SelectionBox:follow(target)
    local node = self.node
    if not target or target.destroyed then
        if node.visible then
            node.visible = false
        end
        return
    end
    node.position = { target.position[1], target.position[2], target.position[3] }
    node.rotation = { target.rotation[1], target.rotation[2], target.rotation[3] }
    local size = target.size or { 1, 1, 1 }
    node.size = { size[1], size[2], size[3] }
    if not node.visible then
        node.visible = true
    end
end

function SelectionBox:release()
    if self.node and not self.node.destroyed then
        self.node:destroy()
    end
end

return SelectionBox
