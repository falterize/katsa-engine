local RenderRange = require('../components.renderRange')
-- Per-World3D registry of Beam3D and Trail3D nodes. `prepare` builds each visible ribbon's centre
-- line once per rendered frame and hands it to the transparent draw list.
local Layering = require('../components.layering')
local Geometry = require('./geometry')
local Source = require('./source')

local System = {}
System.__index = System

function System.new(world)
    return setmetatable({
        world = world,
        nodes = {},
        stats = { drawCalls = 0, rendered = 0, drawMilliseconds = 0, visible = 0 },
    }, System)
end

function System:add(node)
    self.nodes[#self.nodes + 1] = node
end

function System:remove(node)
    for i, item in ipairs(self.nodes) do
        if item == node then
            table.remove(self.nodes, i)
            break
        end
    end
    if node._mesh then
        node._mesh:release()
        node._mesh = nil
    end
    node._vertices, node._meshCapacity = nil, 0
end

-- True while any ribbon changes the picture (used by the render cache to stay dynamic).
function System:active()
    for _, node in ipairs(self.nodes) do
        if node.enabled ~= false and node.visible ~= false then
            return true
        end
    end
    return false
end

-- Builds the centre line of one node for this frame. Returns the point count (0 = nothing to draw).
function System:build(node, time)
    if node.ribbonKind == 'Beam3D' then
        return Source.beam(node)
    end
    Source.sampleTrail(node, time)
    return Source.trail(node, time)
end

-- Appends visible ribbons to `list` (the transparent items) and returns the number added.
function System:prepare(camera, list)
    local world = self.world
    local time = world.simulationTime or 0
    local added = 0
    self.stats.drawCalls, self.stats.rendered, self.stats.drawMilliseconds = 0, 0, 0
    local detail = world.ribbonDetail or 1
    for _, node in ipairs(self.nodes) do
        world:resolveLayerGroup(node)
        node._detail = detail
        node._count = 0
        if
            node.enabled ~= false
            and node:isVisible()
            and node:getEffectiveOpacity() > 0
            and Layering.sees(camera, node)
        then
            local n = self:build(node, time)
            if n >= 2 then
                local cx, cy, cz, radius = Geometry.bounds(node._points, n)
                local center = node._center or {}
                node._center = center
                center[1], center[2], center[3] = cx, cy, cz
                node._radius = radius
                local position = camera.worldPosition or camera.position
                local dx, dy, dz = cx - position[1], cy - position[2], cz - position[3]
                if
                    RenderRange.within(node.maxDistance, dx * dx + dy * dy + dz * dz, radius)
                    and camera:visible(center, radius)
                then
                    node._count = n
                    node.depth = dx * camera.forward[1] + dy * camera.forward[2] + dz * camera.forward[3]
                    node.depth = node.depth + node.zOffset
                    list[#list + 1] = node
                    added = added + 1
                end
            end
        end
    end
    self.stats.visible = added
    return added
end

function System:draw(camera, node)
    return require('source.engine.ribbons.renderer').draw(self, camera, node)
end

return System
