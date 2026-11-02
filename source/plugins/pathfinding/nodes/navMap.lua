-- NavMap: a baked navigation map for a region of the world, the engine's counterpart of Godot's
-- NavigationRegion. The scene needs `plugins = { 'pathfinding' }` in its settings.
--
--   local map = world:create('NavMap', { position = { 0, 0, 0 }, areaSize = { 120, 120 } })
--   map:bake()                                        -- samples the physics world
--   local path = map:findPath({ x, y, z }, { x2, y2, z2 })
--
-- Baking casts one ray per cell and floor straight down. A cell is walkable when the surface it
-- hits is flatter than `maxSlope`, has `agentHeight` of free space above it and no cliff (a jump
-- larger than `maxStep`) next to it; blocked cells grow by `agentRadius`. Several storeys (a car
-- park, a bridge) use `floors` > 1: each collider says which floor it is the ground of with the
-- `navFloor` setting the plugin adds to Body3D (0/1 = the first floor). A floor only sees colliders
-- of its own number, while every collider blocks headroom. Floors are joined wherever their
-- surfaces meet, such as the foot of a ramp.
local Pathfinding = require('../../pathfinding')

local NavMap = {
    base = 'Node3D',
    properties = {
        areaSize = { default = { 100, 100 }, hint = 'Width and depth (X, Z) of the baked region, centered on the node.' },
        cellSize = { default = 2, min = 0.25, hint = 'Edge of one navigation cell, in world units. Smaller is more exact and slower to bake.' },
        floors = { default = 1, min = 1, hint = 'Number of storeys (car park, bridge). A collider belongs to a floor through its navFloor setting.' },
        castTop = { default = 50, hint = 'Height above the node where baking rays start.' },
        castBottom = { default = -50, hint = 'Height below the node where baking rays stop.' },
        agentRadius = { default = 1.5, min = 0, hint = 'Blocked cells grow by whole cells of this radius (radius / cellSize, rounded down) so routes keep clear of walls.' },
        agentHeight = { default = 1.5, min = 0, hint = 'Free height a cell needs above its surface.' },
        maxSlope = { default = 35, min = 0, max = 89, hint = 'Steepest walkable surface, in degrees.' },
        maxStep = { default = 0.6, min = 0, hint = 'Largest height jump between neighboring cells before the edge counts as a cliff; also joins floors.' },
    },
}

local RECENT = 8

function NavMap.initialize(self)
    self.map, self.baked, self.recent = nil, false, {}
end

-- Called when the map is baked: the debug view finds maps through the world's list.
local function register(self)
    local world = self._world or self._sceneWorld
    if world then
        world.navMaps = world.navMaps or {}
        for _, known in ipairs(world.navMaps) do
            if known == self then
                return
            end
        end
        world.navMaps[#world.navMaps + 1] = self
    end
end

function NavMap:getMap()
    return self.map
end

function NavMap:isBaked()
    return self.baked
end

-- Colliders can opt out with `navWalkable`; `navFloor` picks the floor a collider is ground of.
local function blocksHeadroom(body)
    local node = body.object or body
    return node.navWalkable ~= false
end

local function groundOf(floor)
    return function(body)
        local node = body.object or body
        if node.navWalkable == false then
            return false
        end
        local own = node.navFloor or 0
        return own == floor or floor == 1 and own == 0
    end
end

local function column(physics, node, x, z, ground, cosSlope)
    local y0 = node.position[2]
    local top, bottom = y0 + node.castTop, y0 + node.castBottom
    local hit = physics:raycast({ x, top, z }, { x, bottom, z }, ground, {})
    if not hit then
        return
    end
    local height = hit.position[2]
    if hit.normal[2] < cosSlope then
        return height, true -- too steep to stand on
    end
    local roof = physics:raycast({ x, height + 0.05, z }, { x, height + node.agentHeight, z }, blocksHeadroom, {})
    return height, roof ~= nil
end

-- Marks cells next to blocked ones (Chebyshev distance `rings`) as blocked.
local function grow(blocked, width, height, rings)
    for _ = 1, rings do
        local grown = {}
        for cz = 1, height do
            for cx = 1, width do
                local index = (cz - 1) * width + cx
                if blocked[index] then
                    for dz = -1, 1 do
                        for dx = -1, 1 do
                            local nx, nz = cx + dx, cz + dz
                            if nx >= 1 and nz >= 1 and nx <= width and nz <= height then
                                grown[(nz - 1) * width + nx] = true
                            end
                        end
                    end
                end
            end
        end
        for index in pairs(grown) do
            blocked[index] = true
        end
    end
end

-- Samples the physics world and builds the navigation layers. Returns the number of walkable
-- cells. `physics` defaults to the node's world physics.
function NavMap:bake(physics)
    physics = physics or (self._world or self._sceneWorld or {}).physics
    assert(physics, 'NavMap needs a physics world to bake')
    local size, cellSize = self.areaSize, self.cellSize
    local width, depth = math.ceil(size[1] / cellSize), math.ceil(size[2] / cellSize)
    local originX = self.position[1] - width * cellSize / 2
    local originZ = self.position[3] - depth * cellSize / 2
    local cosSlope = math.cos(math.rad(self.maxSlope))
    local map = Pathfinding.Layered.new(width, depth, {
        levels = self.floors,
        cellSize = cellSize,
        origin = { originX, originZ },
    })
    local blockedLayers, heightLayers = {}, {}
    local rings = math.floor(self.agentRadius / cellSize)
    for level = 1, self.floors do
        local ground = groundOf(level)
        local blocked, heights = {}, {}
        for cz = 1, depth do
            for cx = 1, width do
                local index = (cz - 1) * width + cx
                local x = originX + (cx - 0.5) * cellSize
                local z = originZ + (cz - 0.5) * cellSize
                local height, closed = column(physics, self, x, z, ground, cosSlope)
                heights[index] = height
                blocked[index] = height == nil or closed or nil
            end
        end
        local raw, dropped = {}, {}
        for index, height in pairs(heights) do
            raw[index] = height
        end
        for lower = 1, level - 1 do
            for index, height in pairs(raw) do
                local below = heightLayers[lower][index]
                if below and math.abs(below - height) < 0.1 then
                    heights[index], dropped[index] = nil, true
                end
            end
        end
        -- A cliff blocks both of its edge cells; the dropped surface still counts as the far
        -- side of an edge (the ground beside a ramp), but is not an obstacle itself.
        local cliffs = {}
        for cz = 1, depth do
            for cx = 1, width do
                local index = (cz - 1) * width + cx
                local here = raw[index]
                if here and not blocked[index] and not dropped[index] then
                    for _, offset in ipairs({ { 1, 0 }, { 0, 1 }, { -1, 0 }, { 0, -1 } }) do
                        local nx, nz = cx + offset[1], cz + offset[2]
                        local other = nx >= 1 and nz >= 1 and nx <= width and nz <= depth
                            and raw[(nz - 1) * width + nx]
                        if other and math.abs(other - here) > self.maxStep then
                            cliffs[index] = true
                        end
                    end
                end
            end
        end
        for index in pairs(cliffs) do
            blocked[index] = true
        end
        grow(blocked, width, depth, rings)
        for index in pairs(dropped) do
            blocked[index] = true
        end
        blockedLayers[level], heightLayers[level] = blocked, heights
    end
    map:bake(function(level, x, z)
        local cx, cz = map:toCell(x, z)
        return blockedLayers[level][(cz - 1) * width + cx] == true
    end, function(level, x, z)
        local cx, cz = map:toCell(x, z)
        return heightLayers[level][(cz - 1) * width + cx]
    end)
    -- Join floors whose free cells touch at a similar height (a ramp meeting the ground).
    local reach = rings + 1
    for level = 1, self.floors - 1 do
        for other = level + 1, self.floors do
            for cz = 1, depth do
                for cx = 1, width do
                    local index = (cz - 1) * width + cx
                    if not blockedLayers[level][index] then
                        for dz = -reach, reach do
                            for dx = -reach, reach do
                                local nx, nz = cx + dx, cz + dz
                                if nx >= 1 and nz >= 1 and nx <= width and nz <= depth then
                                    local near = (nz - 1) * width + nx
                                    if
                                        not blockedLayers[other][near]
                                        and math.abs(heightLayers[other][near] - heightLayers[level][index])
                                            <= self.maxStep
                                    then
                                        local ax, az = map.levels[level]:toWorld(cx, cz)
                                        local bx, bz = map.levels[other]:toWorld(nx, nz)
                                        map:link(level, ax, az, other, bx, bz)
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
    end
    self.map, self.baked = map, true
    register(self)
    local free = 0
    for level = 1, self.floors do
        for index = 1, width * depth do
            free = free + (blockedLayers[level][index] and 0 or 1)
        end
    end
    return free
end

-- Route between { x, y, z } points (y = the height of the surface, or of a car above it).
-- Returns a Path with { x, y, z } points and `levels`, or nil, reason. The last routes are kept
-- for the debug view.
function NavMap:findPath(from, to, options)
    assert(self.baked, 'NavMap is not baked: call bake() first')
    local path, reason = self.map:findPath(from[1], from[2], from[3], to[1], to[2], to[3], options)
    if path then
        table.insert(self.recent, 1, path)
        self.recent[RECENT + 1] = nil
    end
    return path, reason
end

function NavMap:levelAt(x, y, z, tolerance)
    return self.map and self.map:levelAt(x, y, z, tolerance)
end

return NavMap
