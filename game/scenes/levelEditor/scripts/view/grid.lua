-- The ground grid: one mesh of thin double-sided quads on the XZ plane (minor lines, major
-- lines every `major` cells, the X axis in red and the Z axis in blue). It follows the camera in
-- whole major steps, so it looks endless; it is rebuilt only when the cell size changes.
local Geometry = require('source.engine.graphics.geometry.primitives')

local Grid = {}
Grid.__index = Grid

local MINOR = { 0.45, 0.47, 0.5, 1 }
local MAJOR = { 0.7, 0.72, 0.76, 1 }
local AXIS_X = { 0.9, 0.25, 0.25, 1 }
local AXIS_Z = { 0.3, 0.45, 0.95, 1 }

-- Vertex format of the engine's meshes: x y z u v nx ny nz.
local function quad(vertices, x0, z0, x1, z1)
    local function v(x, z, up)
        return { x, 0, z, 0, 0, 0, up, 0 }
    end
    for _, up in ipairs({ 1, -1 }) do
        local a, b, c, d = v(x0, z0, up), v(x1, z0, up), v(x1, z1, up), v(x0, z1, up)
        if up == 1 then
            vertices[#vertices + 1], vertices[#vertices + 2], vertices[#vertices + 3] = a, d, c
            vertices[#vertices + 1], vertices[#vertices + 2], vertices[#vertices + 3] = a, c, b
        else
            vertices[#vertices + 1], vertices[#vertices + 2], vertices[#vertices + 3] = a, c, d
            vertices[#vertices + 1], vertices[#vertices + 2], vertices[#vertices + 3] = a, b, c
        end
    end
end

-- One mesh per colour class, so each keeps a single flat colour.
local function build(cell, major, count)
    local classes = { minor = {}, major = {}, axisX = {}, axisZ = {} }
    local extent = count * cell
    local thin = cell * 0.012
    for i = -count, count do
        local at = i * cell
        local class = (i == 0) and 'axis' or ((i % major == 0) and 'major' or 'minor')
        -- Lines parallel to Z sit at x = at; lines parallel to X sit at z = at.
        local alongZ = class == 'axis' and classes.axisZ or classes[class]
        local alongX = class == 'axis' and classes.axisX or classes[class]
        local t = class == 'minor' and thin or thin * 2
        quad(alongZ, at - t, -extent, at + t, extent)
        quad(alongX, -extent, at - t, extent, at + t)
    end
    return classes
end

function Grid.new(world, parent, settings)
    local self = setmetatable({ world = world, settings = settings, nodes = {} }, Grid)
    self.cell, self.visible = settings.cell, settings.visible
    self.root = world:create('Node3D', { name = 'EditorGrid' }, parent)
    self:rebuild()
    return self
end

local COLORS = { minor = MINOR, major = MAJOR, axisX = AXIS_X, axisZ = AXIS_Z }

function Grid:rebuild()
    for _, node in pairs(self.nodes) do
        node:destroy()
    end
    self.nodes = {}
    local classes = build(self.cell, self.settings.major, self.settings.count)
    for name, vertices in pairs(classes) do
        self.nodes[name] = self.world:create('Mesh3D', {
            name = 'Grid_' .. name,
            geometry = Geometry.mesh(vertices),
            color = COLORS[name],
            lightInfluence = 0,
            canQuery = false,
            castShadow = false,
            position = { 0, 0.001, 0 },
            visible = self.visible,
        }, self.root)
    end
    self.step = self.cell * self.settings.major
    self.lastX, self.lastZ = nil, nil
end

function Grid:setCell(cell)
    if cell > 0 and cell ~= self.cell then
        self.cell = cell
        self:rebuild()
    end
end

-- Lines between two bright ones, and how many cells the grid patch covers each way.
function Grid:setMajor(major)
    major = math.floor(major)
    if major >= 1 and major ~= self.settings.major then
        self.settings.major = major
        self:rebuild()
    end
end

function Grid:setCount(count)
    count = math.floor(count)
    if count >= 2 and count <= 400 and count ~= self.settings.count then
        self.settings.count = count
        self:rebuild()
    end
end

function Grid:setVisible(visible)
    self.visible = visible
    for _, node in pairs(self.nodes) do
        node.visible = visible
    end
end

-- The axis lines stay at the origin; only the minor and major lines follow the camera.
function Grid:follow(x, z)
    local step = self.step
    local gx, gz = math.floor(x / step + 0.5) * step, math.floor(z / step + 0.5) * step
    if gx == self.lastX and gz == self.lastZ then
        return
    end
    self.lastX, self.lastZ = gx, gz
    for _, name in ipairs({ 'minor', 'major' }) do
        local node = self.nodes[name]
        if node then
            node.position = { gx, 0.001, gz }
        end
    end
end

function Grid:release()
    if self.root and not self.root.destroyed then
        self.root:destroy()
    end
    self.nodes = {}
end

return Grid
