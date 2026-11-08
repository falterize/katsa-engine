-- Voxelisation of a triangle soup: marks the cells the surface passes through, then flood-fills the
-- outside so that a closed model also fills its inside. An open (not watertight) model simply keeps
-- its surface cells.
--
-- Cells are addressed by 0-based integer coordinates (i, j, k); `index(i, j, k)` gives the slot in
-- `filled` (a flat array of booleans). The grid has one empty cell of padding on every side, so the
-- cell (0, 0, 0) is always outside.
local Grid = {}
Grid.__index = Grid

local floor, ceil, sqrt = math.floor, math.ceil, math.sqrt

local function edgeLength(p, q)
    return sqrt((p[1] - q[1]) ^ 2 + (p[2] - q[2]) ^ 2 + (p[3] - q[3]) ^ 2)
end

-- soup: list of vertices, three per triangle ({x, y, z}); resolution: cells along the longest side.
function Grid.build(soup, resolution)
    local minX, minY, minZ = math.huge, math.huge, math.huge
    local maxX, maxY, maxZ = -math.huge, -math.huge, -math.huge
    for i = 1, #soup do
        local p = soup[i]
        minX, maxX = math.min(minX, p[1]), math.max(maxX, p[1])
        minY, maxY = math.min(minY, p[2]), math.max(maxY, p[2])
        minZ, maxZ = math.min(minZ, p[3]), math.max(maxZ, p[3])
    end
    local longest = math.max(maxX - minX, maxY - minY, maxZ - minZ)
    assert(longest > 0, 'Cannot voxelise an empty or single-point model')
    local size = longest / resolution
    local self = setmetatable({
        size = size,
        originX = minX - size,
        originY = minY - size,
        originZ = minZ - size,
        nx = ceil((maxX - minX) / size) + 2,
        ny = ceil((maxY - minY) / size) + 2,
        nz = ceil((maxZ - minZ) / size) + 2,
    }, Grid)
    local total = self.nx * self.ny * self.nz
    local state = {} -- 0 empty, 1 surface, 2 outside
    for i = 1, total do
        state[i] = 0
    end
    self.state = state
    self:markSurface(soup)
    self:floodOutside()
    return self
end

function Grid:index(i, j, k)
    return i + self.nx * (j + self.ny * k) + 1
end

function Grid:isFilled(i, j, k)
    return self.state[i + self.nx * (j + self.ny * k) + 1] ~= 2
end

-- Samples every triangle densely enough (a third of a cell) that the marked cells form a
-- connected skin no 6-connected flood can leak through.
function Grid:markSurface(soup)
    local size, state = self.size, self.state
    local ox, oy, oz = self.originX, self.originY, self.originZ
    local nx, ny, nz = self.nx, self.ny, self.nz
    local step = size / 3
    for t = 1, #soup - 2, 3 do
        local a, b, c = soup[t], soup[t + 1], soup[t + 2]
        local longest = math.max(edgeLength(a, b), edgeLength(b, c), edgeLength(c, a))
        local n = math.max(1, ceil(longest / step))
        local abx, aby, abz = (b[1] - a[1]) / n, (b[2] - a[2]) / n, (b[3] - a[3]) / n
        local acx, acy, acz = (c[1] - a[1]) / n, (c[2] - a[2]) / n, (c[3] - a[3]) / n
        for u = 0, n do
            for v = 0, n - u do
                local i = floor((a[1] + abx * u + acx * v - ox) / size)
                local j = floor((a[2] + aby * u + acy * v - oy) / size)
                local k = floor((a[3] + abz * u + acz * v - oz) / size)
                if i >= 0 and i < nx and j >= 0 and j < ny and k >= 0 and k < nz then
                    state[i + nx * (j + ny * k) + 1] = 1
                end
            end
        end
    end
end

-- Marks every empty cell reachable from the padding corner as outside (state 2).
function Grid:floodOutside()
    local state, nx, ny, nz = self.state, self.nx, self.ny, self.nz
    local stack, top = { 1 }, 1
    state[1] = 2
    local layer = nx * ny
    local function push(neighbor)
        if state[neighbor] == 0 then
            state[neighbor] = 2
            top = top + 1
            stack[top] = neighbor
        end
    end
    while top > 0 do
        local cell = stack[top]
        top = top - 1
        local index = cell - 1
        local i = index % nx
        local j = floor(index / nx) % ny
        local k = floor(index / layer)
        if i > 0 then
            push(cell - 1)
        end
        if i < nx - 1 then
            push(cell + 1)
        end
        if j > 0 then
            push(cell - nx)
        end
        if j < ny - 1 then
            push(cell + nx)
        end
        if k > 0 then
            push(cell - layer)
        end
        if k < nz - 1 then
            push(cell + layer)
        end
    end
end

return Grid
