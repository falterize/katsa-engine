-- NavMesh: a tiled, baked navigation mesh of convex polygons (merged rectangles of free cells),
-- one polygon layer per floor. It is built from the same cell samples a NavMap bakes (blocked
-- flags and surface heights per floor) and answers routes as straight, string-pulled paths.
--
-- Tiles make it dynamic: obstacles cover cells and mark their tiles dirty; the next query (or
-- `refresh`) re-merges only those tiles and reconnects them to their neighbours. Polygon ids are
-- never reused, so anything holding an old id can detect that its polygon is gone.
local Merge = require('./merge')

local Mesh = {}
Mesh.__index = Mesh

-- options: width, depth (cells), cellSize, origin = { x, z }, levels (floors), tile (cells per
-- tile side), flatness (largest height difference inside one polygon), agentRadius (obstacle
-- inflation).
function Mesh.new(options)
    local self = setmetatable({
        width = options.width,
        depth = options.depth,
        cellSize = options.cellSize or 1,
        originX = (options.origin or { 0, 0 })[1],
        originZ = (options.origin or { 0, 0 })[2],
        levels = options.levels or 1,
        tile = options.tile or 16,
        flatness = options.flatness or 0.3,
        agentRadius = options.agentRadius or 0,
        blocked = {},
        heights = {},
        dynamic = {},
        owner = {},
        polygons = {},
        tilePolygons = {},
        dirty = {},
        cellLinks = {},
        obstacles = {},
        revision = 0,
        nextId = 0,
    }, Mesh)
    self.tilesX = math.ceil(self.width / self.tile)
    self.tilesZ = math.ceil(self.depth / self.tile)
    for level = 1, self.levels do
        self.blocked[level], self.heights[level] = {}, {}
        self.dynamic[level], self.owner[level], self.cellLinks[level] = {}, {}, {}
    end
    return self
end

function Mesh:index(cx, cz)
    return (cz - 1) * self.width + cx
end

function Mesh:inside(cx, cz)
    return cx >= 1 and cz >= 1 and cx <= self.width and cz <= self.depth
end

function Mesh:toCell(x, z)
    return math.floor((x - self.originX) / self.cellSize) + 1,
        math.floor((z - self.originZ) / self.cellSize) + 1
end

function Mesh:toWorld(cx, cz)
    return self.originX + (cx - 0.5) * self.cellSize, self.originZ + (cz - 0.5) * self.cellSize
end

function Mesh:tileKey(cx, cz)
    return math.floor((cz - 1) / self.tile) * self.tilesX + math.floor((cx - 1) / self.tile) + 1
end

function Mesh:markDirty(cx, cz)
    self.dirty[self:tileKey(cx, cz)] = true
end

-- A cell is free when it has a surface, is not statically blocked and no obstacle covers it.
function Mesh:isFree(level, cx, cz)
    if not self:inside(cx, cz) then
        return false
    end
    local index = self:index(cx, cz)
    return self.heights[level][index] ~= nil
        and not self.blocked[level][index]
        and (self.dynamic[level][index] or 0) == 0
end

-- Sets the static layers: blocked[level][index] flags and heights[level][index] surfaces, both
-- indexed (cz - 1) * width + cx. The tables are copied.
function Mesh:load(blocked, heights)
    for level = 1, self.levels do
        local b, h = {}, {}
        for index, value in pairs(blocked[level] or {}) do
            b[index] = value
        end
        for index, value in pairs(heights[level] or {}) do
            h[index] = value
        end
        self.blocked[level], self.heights[level] = b, h
    end
    for key = 1, self.tilesX * self.tilesZ do
        self.dirty[key] = true
    end
    self:refresh()
end

-- Joins two floors at a pair of world points (a ramp foot and its top), in both directions.
function Mesh:link(levelA, ax, az, levelB, bx, bz)
    local acx, acz = self:toCell(ax, az)
    local bcx, bcz = self:toCell(bx, bz)
    local function add(level, cx, cz, other, ocx, ocz)
        local index = self:index(cx, cz)
        local list = self.cellLinks[level][index] or {}
        self.cellLinks[level][index] = list
        for _, existing in ipairs(list) do
            if existing[1] == other and existing[2] == ocx and existing[3] == ocz then
                return
            end
        end
        list[#list + 1] = { other, ocx, ocz }
        self:markDirty(cx, cz)
    end
    add(levelA, acx, acz, levelB, bcx, bcz)
    add(levelB, bcx, bcz, levelA, acx, acz)
end

local function newPolygon(self, level, cx0, cz0, cx1, cz1, tile)
    self.nextId = self.nextId + 1
    local x0, z0 = self.originX + (cx0 - 1) * self.cellSize, self.originZ + (cz0 - 1) * self.cellSize
    local x1, z1 = self.originX + cx1 * self.cellSize, self.originZ + cz1 * self.cellSize
    local polygon = {
        id = self.nextId,
        level = level,
        tile = tile,
        cx0 = cx0,
        cz0 = cz0,
        cx1 = cx1,
        cz1 = cz1,
        x0 = x0,
        z0 = z0,
        x1 = x1,
        z1 = z1,
        centerX = (x0 + x1) / 2,
        centerZ = (z0 + z1) / 2,
        edges = {},
        links = {},
    }
    self.polygons[polygon.id] = polygon
    for cz = cz0, cz1 do
        for cx = cx0, cx1 do
            local index = self:index(cx, cz)
            self.owner[level][index] = polygon.id
            local list = self.cellLinks[level][index]
            if list then
                for _, link in ipairs(list) do
                    polygon.links[#polygon.links + 1] = { cx = cx, cz = cz, level = link[1], ocx = link[2], ocz = link[3] }
                end
            end
        end
    end
    return polygon
end

local function dropTile(self, key)
    for _, id in ipairs(self.tilePolygons[key] or {}) do
        local polygon = self.polygons[id]
        for cz = polygon.cz0, polygon.cz1 do
            for cx = polygon.cx0, polygon.cx1 do
                self.owner[polygon.level][self:index(cx, cz)] = nil
            end
        end
        self.polygons[id] = nil
    end
    self.tilePolygons[key] = {}
end

local function buildTile(self, key)
    dropTile(self, key)
    local tx, tz = (key - 1) % self.tilesX, math.floor((key - 1) / self.tilesX)
    local cx0, cz0 = tx * self.tile + 1, tz * self.tile + 1
    local cx1, cz1 = math.min(self.width, cx0 + self.tile - 1), math.min(self.depth, cz0 + self.tile - 1)
    local list = {}
    for level = 1, self.levels do
        local heights = self.heights[level]
        Merge.tile(
            cx0,
            cz0,
            cx1,
            cz1,
            function(cx, cz)
                return self:isFree(level, cx, cz)
            end,
            function(cx, cz)
                return heights[self:index(cx, cz)]
            end,
            self.flatness,
            function(a, b, c, d)
                list[#list + 1] = newPolygon(self, level, a, b, c, d, key).id
            end
        )
    end
    self.tilePolygons[key] = list
end

-- Portals (shared border segments) of one polygon, found from the owners next to its sides.
local function connect(self, polygon)
    local edges = {}
    polygon.edges = edges
    local owner = self.owner[polygon.level]
    local cell = self.cellSize
    local function side(fixed, from, to, horizontal, outside)
        -- Walk the border cells; every run with the same neighbouring polygon is one portal.
        local run, runStart
        local function close(last)
            if run then
                local a, b = from + (runStart - 1) * cell, from + last * cell
                local edge
                if horizontal then
                    edge = { to = run, x1 = a, z1 = fixed, x2 = b, z2 = fixed }
                else
                    edge = { to = run, x1 = fixed, z1 = a, x2 = fixed, z2 = b }
                end
                edge.mx, edge.mz = (edge.x1 + edge.x2) / 2, (edge.z1 + edge.z2) / 2
                edges[#edges + 1] = edge
                run = nil
            end
        end
        for step = 1, to do
            local cx, cz = outside(step)
            local id = self:inside(cx, cz) and owner[self:index(cx, cz)] or nil
            if id ~= run then
                close(step - 1)
                run, runStart = id, step
            end
        end
        close(to)
    end
    local width, height = polygon.cx1 - polygon.cx0 + 1, polygon.cz1 - polygon.cz0 + 1
    side(polygon.z0, polygon.x0, width, true, function(step)
        return polygon.cx0 + step - 1, polygon.cz0 - 1
    end)
    side(polygon.z1, polygon.x0, width, true, function(step)
        return polygon.cx0 + step - 1, polygon.cz1 + 1
    end)
    side(polygon.x0, polygon.z0, height, false, function(step)
        return polygon.cx0 - 1, polygon.cz0 + step - 1
    end)
    side(polygon.x1, polygon.z0, height, false, function(step)
        return polygon.cx1 + 1, polygon.cz0 + step - 1
    end)
end

-- Re-merges the dirty tiles and reconnects them with their neighbours. Cheap when nothing
-- changed. Bumps `revision`, which followers compare to know their route may be stale.
function Mesh:refresh()
    if not next(self.dirty) then
        return false
    end
    local touched = {}
    for key in pairs(self.dirty) do
        buildTile(self, key)
        local tx, tz = (key - 1) % self.tilesX, math.floor((key - 1) / self.tilesX)
        for dz = -1, 1 do
            for dx = -1, 1 do
                local nx, nz = tx + dx, tz + dz
                if nx >= 0 and nz >= 0 and nx < self.tilesX and nz < self.tilesZ then
                    touched[nz * self.tilesX + nx + 1] = true
                end
            end
        end
    end
    for key in pairs(touched) do
        for _, id in ipairs(self.tilePolygons[key] or {}) do
            connect(self, self.polygons[id])
        end
    end
    self.dirty = {}
    self.revision = self.revision + 1
    return true
end

function Mesh:polygonCount()
    local count = 0
    for _ in pairs(self.polygons) do
        count = count + 1
    end
    return count
end

return Mesh
