-- Body dents. A dent is a small record in car space, so the whole damage state is a short list
-- that can be replicated and replayed on every machine: { x, y, z, dx, dz, depth, radius, dy }.
-- (dx, dz) is the unit push direction (into the body). Vertices near the dent move along it.
local Deformation = {}
Deformation.__index = Deformation

local MAX_DENTS = 24
local MAX_DEPTH = 0.7
local CRUMPLE = 0.32 -- facet noise on the pushed panel, as a share of the local depth
local PINCH = 0.22 -- how much the metal around the impact is drawn toward its centre

function Deformation.new(options)
    options = options or {}
    return setmetatable({
        dents = {},
        maxDents = options.maxDents or MAX_DENTS,
        maxDepth = options.maxDepth or MAX_DEPTH,
        minSpeed = options.minSpeed or 3,
        halfLength = options.halfLength or 2.6,
        halfWidth = options.halfWidth or 0.98,
    }, Deformation)
end

-- Adds a dent from a collision impact (see collision.lua). Gentle bumps are ignored.
-- Returns the dent, or nil when the impact was too weak.
function Deformation:addImpact(impact)
    if impact.speed < self.minSpeed then
        return nil
    end
    local depth = math.min(self.maxDepth, (impact.speed - self.minSpeed) * 0.045 + 0.06)
    local dent = {
        x = impact.x,
        y = impact.y or 0.5,
        z = impact.z,
        dx = impact.nx,
        dy = impact.ny or 0,
        dz = impact.nz,
        depth = depth,
        radius = 0.8 + depth * 1.6, -- a harder hit bends a wider area
    }
    return self:add(dent)
end

function Deformation:add(dent)
    local dents = self.dents
    if #dents >= self.maxDents then
        -- Merge into the nearest existing dent so damage keeps accumulating without growing.
        local best, bestDistance = 1, math.huge
        for index, other in ipairs(dents) do
            local distance = (other.x - dent.x) ^ 2 + (other.z - dent.z) ^ 2
            if distance < bestDistance then
                best, bestDistance = index, distance
            end
        end
        local target = dents[best]
        target.depth = math.min(self.maxDepth, target.depth + dent.depth * 0.5)
        return target
    end
    dents[#dents + 1] = dent
    return dent
end

function Deformation:clear()
    self.dents = {}
end

-- A repeatable value in -1..1 for a point of the rest pose: the same on every machine, so the
-- crumpled facets of a replicated dent look identical everywhere.
local function facet(x, y, z)
    local h = math.sin(x * 127.1 + y * 311.7 + z * 74.7) * 43758.5453
    return (h - math.floor(h)) * 2 - 1
end

-- Displacement of a point at car-space (x, y, z). The metal is pushed along the hit direction,
-- drawn toward the impact point and crinkled into facets; the smooth falloff keeps the lattice
-- continuous at the rim of the dent.
function Deformation:offsetAt(x, y, z)
    local ox, oy, oz = 0, 0, 0
    for _, dent in ipairs(self.dents) do
        local ddx, ddy, ddz = x - dent.x, y - dent.y, z - dent.z
        local distance = math.sqrt(ddx * ddx + ddy * ddy + ddz * ddz)
        if distance < dent.radius then
            local t = 1 - distance / dent.radius
            local weight = t * t * (3 - 2 * t) * dent.depth
            local push = weight * (1 + CRUMPLE * facet(x, y, z))
            ox = ox + dent.dx * push
            oz = oz + dent.dz * push
            -- Pushed in along the hit direction; a little extra sag makes the panel crumple.
            oy = oy + (dent.dy or 0) * push - weight * 0.1
            if distance > 1e-4 then
                local pull = weight * PINCH * t / distance
                ox, oy, oz = ox - ddx * pull, oy - ddy * pull, oz - ddz * pull
            end
        end
    end
    return ox, oy, oz
end

-- True when the sphere of any dent touches the box [min, max] (car space): parts out of reach
-- of every dent keep their rest pose and need no work.
function Deformation:touches(minX, minY, minZ, maxX, maxY, maxZ)
    for _, dent in ipairs(self.dents) do
        local dx = math.max(minX - dent.x, 0, dent.x - maxX)
        local dy = math.max(minY - dent.y, 0, dent.y - maxY)
        local dz = math.max(minZ - dent.z, 0, dent.z - maxZ)
        if dx * dx + dy * dy + dz * dz < dent.radius * dent.radius then
            return true
        end
    end
    return false
end

-- Builds a box lattice (segments per axis) of car-space points for a body of the given size.
-- Returns a flat list of { x, y, z } so a renderer can move vertices by offsetAt().
function Deformation.lattice(width, height, length, segments)
    segments = segments or 6
    local points = {}
    for i = 0, segments do
        for j = 0, 2 do
            for k = 0, segments do
                points[#points + 1] = {
                    (i / segments - 0.5) * width,
                    j / 2 * height,
                    (k / segments - 0.5) * length,
                }
            end
        end
    end
    return points
end

function Deformation:serialize()
    local out = {}
    for _, dent in ipairs(self.dents) do
        out[#out + 1] =
            { dent.x, dent.y, dent.z, dent.dx, dent.dz, dent.depth, dent.radius, dent.dy or 0 }
    end
    return out
end

function Deformation:load(list)
    self.dents = {}
    for _, row in ipairs(list or {}) do
        self.dents[#self.dents + 1] = {
            x = row[1],
            y = row[2],
            z = row[3],
            dx = row[4],
            dz = row[5],
            depth = row[6],
            radius = row[7],
            dy = row[8] or 0,
        }
    end
end

return Deformation
