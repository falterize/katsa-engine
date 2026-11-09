-- Queries on a Mesh: locating a point, heights, and routes (A* over polygons, then funnel).
local Heap = require('../heap')
local Path = require('../path')
local Funnel = require('./funnel')

local Query = {}

-- Cost multipliers used when an agent sets none: walking is 1, a jump costs a little more.
Query.defaultActionCosts = { walk = 1, jump = 2 }

-- Multiplier from a costs table (`false` or math.huge forbid; nil = default), or nil when forbidden.
local function costOf(costs, key, default)
    local value = costs and costs[key]
    if value == nil then
        value = default
    end
    if value == false or value == math.huge then
        return nil
    end
    return value
end

local function distance(ax, az, bx, bz)
    return math.sqrt((ax - bx) ^ 2 + (az - bz) ^ 2)
end

function Query.install(Mesh)
    -- Height of the surface at (x, z) on `level`: the cell under the point, or the nearest free
    -- cell around it. nil when there is none.
    function Mesh:heightAt(level, x, z)
        local cx, cz = self:toCell(x, z)
        local heights = self.heights[level]
        local own = self:inside(cx, cz) and heights[self:index(cx, cz)]
        if own then
            return own
        end
        for radius = 1, 2 do
            for dz = -radius, radius do
                for dx = -radius, radius do
                    if self:inside(cx + dx, cz + dz) then
                        local height = heights[self:index(cx + dx, cz + dz)]
                        if height then
                            return height
                        end
                    end
                end
            end
        end
    end

    -- The polygon under (x, z, y), or the nearest one within `snap` cells. Returns polygon, x, z
    -- with the point clamped into the polygon, or nil. Several floors: the one whose surface is
    -- closest to y wins (the lowest when y is nil).
    function Mesh:locate(x, z, y, snap)
        self:refresh()
        snap = snap or 3
        local cx, cz = self:toCell(x, z)
        for ring = 0, snap do
            local best, bestGap
            for level = 1, self.levels do
                local heights = self.heights[level]
                for dz = -ring, ring do
                    for dx = -ring, ring do
                        if math.max(math.abs(dx), math.abs(dz)) == ring and self:isFree(level, cx + dx, cz + dz) then
                            local id = self.owner[level][self:index(cx + dx, cz + dz)]
                            local gap = y and math.abs(heights[self:index(cx + dx, cz + dz)] - y) or level
                            if id and (not bestGap or gap < bestGap) then
                                best, bestGap = id, gap
                            end
                        end
                    end
                end
            end
            if best then
                local polygon = self.polygons[best]
                return polygon,
                    math.max(polygon.x0, math.min(polygon.x1, x)),
                    math.max(polygon.z0, math.min(polygon.z1, z))
            end
        end
    end

    -- Neighbours of a polygon: visit(id, ax, az, bx, bz, edge, link): leave the polygon at
    -- (ax, az) and enter the next one at (bx, bz), through a portal edge or an action link.
    local function expand(self, polygon, visit)
        for _, edge in ipairs(polygon.edges) do
            visit(edge.to, edge.mx, edge.mz, edge.mx, edge.mz, edge, nil)
        end
        for _, link in ipairs(polygon.links) do
            local id = (not link.link or link.link.enabled)
                and self:isFree(link.level, link.ocx, link.ocz)
                and self.owner[link.level][self:index(link.ocx, link.ocz)]
            if id and self:isFree(polygon.level, link.cx, link.cz) then
                local ax, az = self:toWorld(link.cx, link.cz)
                local bx, bz = self:toWorld(link.ocx, link.ocz)
                visit(id, ax, az, bx, bz, nil, link)
            end
        end
    end

    local function portalsOf(self, chain, sx, sz, startPolygon, gx, gz, goalPolygon)
        local portals = { { lx = sx, lz = sz, rx = sx, rz = sz, level = startPolygon.level } }
        for index = 2, #chain do
            local step, from = chain[index], self.polygons[chain[index - 1].id]
            if step.edge then
                local edge = step.edge
                local cross = (edge.x1 - from.centerX) * (edge.z2 - from.centerZ)
                    - (edge.z1 - from.centerZ) * (edge.x2 - from.centerX)
                -- p2 is counter-clockwise of p1 when cross > 0: that one is the left endpoint.
                local lx, lz, rx, rz = edge.x2, edge.z2, edge.x1, edge.z1
                if cross < 0 then
                    lx, lz, rx, rz = edge.x1, edge.z1, edge.x2, edge.z2
                end
                portals[#portals + 1] = { lx = lx, lz = lz, rx = rx, rz = rz, level = from.level }
            else
                local link = step.link
                local ax, az = self:toWorld(link.cx, link.cz)
                local bx, bz = self:toWorld(link.ocx, link.ocz)
                local action = link.link -- nil for a plain floor join
                portals[#portals + 1] = {
                    lx = ax, lz = az, rx = ax, rz = az, level = from.level,
                    link = action, role = action and 'start' or nil,
                }
                portals[#portals + 1] = {
                    lx = bx, lz = bz, rx = bx, rz = bz, level = link.level,
                    link = action, role = action and 'end' or nil,
                }
            end
        end
        portals[#portals + 1] = { lx = gx, lz = gz, rx = gx, rz = gz, level = goalPolygon.level }
        return portals
    end

    -- Route between two world points. Returns a Path of { x, y, z } corners (`path.levels[i]`
    -- is the floor of corner i; `path.revision` the mesh revision it was found on), or nil and a
    -- reason. options: limit (expanded polygons, default 4000), snap (cells, default 3),
    -- areaCosts ({ water = 50 }: cost per unit of walking in an area, default 1; false forbids) and
    -- actionCosts ({ jump = 3 }: cost per unit crossing an action link, jump 2 and others 1 by
    -- default; false forbids). Costs belong to the walker, so every agent can weigh them its way.
    function Mesh:findPath(from, to, options)
        options = options or {}
        local areaCosts, actionCosts = options.areaCosts, options.actionCosts
        local start, sx, sz = self:locate(from[1], from[3], from[2], options.snap)
        local goal, gx, gz = self:locate(to[1], to[3], to[2], options.snap)
        if not start or not goal then
            return nil, 'start or goal is not on the navigation mesh'
        end
        local chain
        if start == goal then
            chain = { { id = start.id } }
        else
            local open, best, came, entry = Heap.new(), { [start.id] = 0 }, {}, { [start.id] = { sx, sz } }
            open:push(start.id, distance(sx, sz, gx, gz))
            local closed, expanded = {}, 0
            local limit = options.limit or 4000
            while not open:isEmpty() do
                local id = open:pop()
                if id == goal.id then
                    break
                end
                if not closed[id] then
                    closed[id] = true
                    expanded = expanded + 1
                    if expanded > limit then
                        return nil, 'search limit reached'
                    end
                    local polygon, here = self.polygons[id], entry[id]
                    -- Walking inside this polygon costs its area multiplier per unit.
                    local walk = costOf(areaCosts, polygon.area, 1) or 1
                    expand(self, polygon, function(next, ax, az, bx, bz, edge, link)
                        local target = self.polygons[next]
                        if not closed[next] and target then
                            local pay = costOf(areaCosts, target.area, 1)
                            local action = link and link.link and link.link.action or 'walk'
                            local hop = costOf(actionCosts, action, Query.defaultActionCosts[action] or 1)
                            if pay and hop then
                                local g = best[id] + distance(here[1], here[2], ax, az) * walk
                                if link then
                                    g = g + distance(ax, az, bx, bz) * hop
                                end
                                if not best[next] or g < best[next] then
                                    best[next], entry[next] = g, { bx, bz }
                                    came[next] = { from = id, edge = edge, link = link }
                                    open:push(next, g + distance(bx, bz, gx, gz))
                                end
                            end
                        end
                    end)
                end
            end
            if not came[goal.id] then
                return nil, 'no route'
            end
            chain = {}
            local id = goal.id
            while id ~= start.id do
                local step = came[id]
                table.insert(chain, 1, { id = id, edge = step.edge, link = step.link })
                id = step.from
            end
            table.insert(chain, 1, { id = start.id })
        end
        local corners = Funnel.pull(portalsOf(self, chain, sx, sz, start, gx, gz, goal))
        local points, levels, roles, links = {}, {}, {}, {}
        for index, corner in ipairs(corners) do
            local height = self:heightAt(corner.level, corner.x, corner.z) or 0
            points[index] = { corner.x, height, corner.z }
            levels[index] = corner.level
            roles[index], links[index] = corner.role, corner.link
        end
        local path = Path.new(points)
        -- roles[i] is 'start' / 'end' for the corners of an action link (links[i] is the link).
        path.levels, path.roles, path.links, path.revision = levels, roles, links, self.revision
        return path
    end

    -- Moves (x, z) toward (nx, nz) and keeps the result on the mesh: a step that leaves it stops
    -- at the nearest mesh point. Returns the new x, z and the polygon.
    function Mesh:clamp(nx, nz, y, snap)
        local polygon, x, z = self:locate(nx, nz, y, snap or 1)
        if not polygon then
            return nil
        end
        return x, z, polygon
    end
end

return Query
