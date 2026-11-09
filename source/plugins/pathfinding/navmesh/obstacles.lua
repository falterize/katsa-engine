-- Dynamic obstacles: shapes that cover cells (inflated by the mesh's agentRadius) so the
-- polygons around them are rebuilt. Moving an obstacle re-covers cells and dirties only the
-- tiles it leaves and enters.
local Obstacles = {}

-- shape: { kind = 'circle', x, z, radius } or { kind = 'box', x, z, halfX, halfZ, angle = 0 }
-- (angle in degrees around Y), optionally { y, height }: only floors whose surface lies within
-- `height` (default 2) of y are blocked; without y every floor is.
local function covers(shape, inflate, x, z)
    local dx, dz = x - shape.x, z - shape.z
    if shape.kind == 'circle' then
        return dx * dx + dz * dz <= (shape.radius + inflate) ^ 2
    end
    local angle = -math.rad(shape.angle or 0)
    local c, s = math.cos(angle), math.sin(angle)
    local lx, lz = dx * c - dz * s, dx * s + dz * c
    return math.abs(lx) <= shape.halfX + inflate and math.abs(lz) <= shape.halfZ + inflate
end

local function extent(shape)
    if shape.kind == 'circle' then
        return shape.radius, shape.radius
    end
    local reach = math.sqrt(shape.halfX ^ 2 + shape.halfZ ^ 2)
    return reach, reach
end

function Obstacles.install(Mesh)
    local function cover(self, obstacle)
        local shape = obstacle.shape
        local reachX, reachZ = extent(shape)
        local inflate = self.agentRadius
        local cx0, cz0 = self:toCell(shape.x - reachX - inflate, shape.z - reachZ - inflate)
        local cx1, cz1 = self:toCell(shape.x + reachX + inflate, shape.z + reachZ + inflate)
        local cells = {}
        for level = 1, self.levels do
            for cz = math.max(1, cz0), math.min(self.depth, cz1) do
                for cx = math.max(1, cx0), math.min(self.width, cx1) do
                    local index = self:index(cx, cz)
                    local height = self.heights[level][index]
                    local x, z = self:toWorld(cx, cz)
                    if
                        height
                        and (not shape.y or math.abs(height - shape.y) <= (shape.height or 2))
                        and covers(shape, inflate, x, z)
                    then
                        local dynamic = self.dynamic[level]
                        dynamic[index] = (dynamic[index] or 0) + 1
                        cells[#cells + 1] = { level, index }
                        self:markDirty(cx, cz)
                    end
                end
            end
        end
        obstacle.cells = cells
    end

    local function uncover(self, obstacle)
        for _, cell in ipairs(obstacle.cells or {}) do
            local dynamic = self.dynamic[cell[1]]
            local count = (dynamic[cell[2]] or 1) - 1
            dynamic[cell[2]] = count > 0 and count or nil
            local cz = math.floor((cell[2] - 1) / self.width) + 1
            self:markDirty(cell[2] - (cz - 1) * self.width, cz)
        end
        obstacle.cells = nil
    end

    -- Adds an obstacle and returns its handle (pass it to moveObstacle / removeObstacle).
    function Mesh:addObstacle(shape)
        assert(shape.kind == 'circle' or shape.kind == 'box', 'Obstacle kind must be circle or box')
        local obstacle = { shape = shape }
        cover(self, obstacle)
        self.obstacles[obstacle] = true
        return obstacle
    end

    -- Re-covers the cells of an obstacle at a new place (and size, when given).
    function Mesh:moveObstacle(obstacle, x, z, change)
        uncover(self, obstacle)
        obstacle.shape.x, obstacle.shape.z = x, z
        for key, value in pairs(change or {}) do
            obstacle.shape[key] = value
        end
        cover(self, obstacle)
    end

    function Mesh:removeObstacle(obstacle)
        if self.obstacles[obstacle] then
            uncover(self, obstacle)
            self.obstacles[obstacle] = nil
        end
    end
end

return Obstacles
