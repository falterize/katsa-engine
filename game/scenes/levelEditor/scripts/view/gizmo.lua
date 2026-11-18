-- The transform gizmos as engine meshes: arrows and plane squares (Move), rings (Rotate),
-- arrows with end cubes and a centre cube (Scale). The meshes are built once in unit size; each
-- frame the root only moves, turns and scales so the gizmo keeps a constant size on screen.
-- Hit testing is geometric (core/gizmoMath), not mesh picking.
local Builder = require('./meshBuilder')
local Geometry = require('source.engine.graphics.geometry.primitives')

local Gizmo = {}
Gizmo.__index = Gizmo

Gizmo.PIXELS = 120 -- gizmo radius on screen

local COLORS = {
    x = { 0.9, 0.22, 0.22, 1 },
    y = { 0.3, 0.8, 0.3, 1 },
    z = { 0.28, 0.45, 0.95, 1 },
    xy = { 0.28, 0.45, 0.95, 0.55 },
    yz = { 0.9, 0.22, 0.22, 0.55 },
    xz = { 0.3, 0.8, 0.3, 0.55 },
    all = { 0.9, 0.9, 0.9, 1 },
}
local HOT = { 1, 0.95, 0.35, 1 }
local AXIS = { { 1, 0, 0 }, { 0, 1, 0 }, { 0, 0, 1 } }
local NAMES = { 'x', 'y', 'z' }

local function axisPoint(index, distance)
    local p = { 0, 0, 0 }
    p[index] = distance
    return p
end

local function build(tool, name)
    local vertices = {}
    local index = ({ x = 1, y = 2, z = 3 })[name]
    if tool == 'Move' then
        if index then
            Builder.bar(vertices, axisPoint(index, 0.12), axisPoint(index, 0.8), { 0, 1, 0 }, 0.012)
            Builder.bar(vertices, axisPoint(index, 0.8), axisPoint(index, 1), { 0, 1, 0 }, 0.045)
        else
            local i, j = ({ xy = 1, yz = 2, xz = 1 })[name], ({ xy = 2, yz = 3, xz = 3 })[name]
            Builder.plate(vertices, i, j, 0.2, 0.5, 0.004)
        end
    elseif tool == 'Rotate' then
        Builder.ring(vertices, index, 1, 0.012, 48)
    elseif index then
        Builder.bar(vertices, axisPoint(index, 0.12), axisPoint(index, 0.85), { 0, 1, 0 }, 0.012)
        Builder.bar(vertices, axisPoint(index, 0.85), axisPoint(index, 1), { 0, 1, 0 }, 0.07)
    else
        Builder.bar(vertices, { -0.07, 0, 0 }, { 0.07, 0, 0 }, { 0, 1, 0 }, 0.07)
    end
    return vertices
end

local LAYOUT = {
    Move = { 'x', 'y', 'z', 'xy', 'yz', 'xz' },
    Rotate = { 'x', 'y', 'z' },
    Scale = { 'x', 'y', 'z', 'all' },
}

function Gizmo.new(world)
    local self = setmetatable({ parts = {}, tool = 'Select' }, Gizmo)
    self.root = world:create('Node3D', { name = 'EditorGizmo', visible = false })
    for _, tool in ipairs({ 'Move', 'Rotate', 'Scale' }) do
        self.parts[tool] = {}
        for _, name in ipairs(LAYOUT[tool]) do
            self.parts[tool][name] = world:create('Mesh3D', {
                name = 'Gizmo' .. tool .. name,
                geometry = Geometry.mesh(build(tool, name)),
                color = COLORS[name],
                lightInfluence = 0,
                canQuery = false,
                castShadow = false,
                visible = false,
            }, self.root)
        end
    end
    return self
end

-- Shows the parts of `tool` (or nothing for Select).
function Gizmo:setTool(tool)
    if tool == self.tool then
        return
    end
    self.tool, self.hot = tool, nil
    for name, parts in pairs(self.parts) do
        for _, node in pairs(parts) do
            node.visible = name == tool
        end
    end
end

-- Places the gizmo: `position` world pivot, `rotation` Euler degrees (zero in World space),
-- `size` world units for the unit gizmo.
function Gizmo:place(position, rotation, size)
    local root = self.root
    root.position = { position[1], position[2], position[3] }
    root.rotation = { rotation[1], rotation[2], rotation[3] }
    root.scale = { size, size, size }
    if not root.visible then
        root.visible = true
    end
end

function Gizmo:hide()
    if self.root.visible then
        self.root.visible = false
    end
end

-- Highlights one handle name (or none) of the current tool.
function Gizmo:highlight(name)
    if name == self.hot then
        return
    end
    local parts = self.parts[self.tool]
    if parts then
        if self.hot and parts[self.hot] then
            parts[self.hot].color = COLORS[self.hot]
        end
        if name and parts[name] then
            parts[name].color = HOT
        end
    end
    self.hot = name
end

function Gizmo:release()
    if self.root and not self.root.destroyed then
        self.root:destroy()
    end
end

Gizmo.AXIS, Gizmo.NAMES = AXIS, NAMES

return Gizmo
