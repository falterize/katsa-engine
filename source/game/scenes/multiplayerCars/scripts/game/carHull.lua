-- The car's collision hull: the body mesh reduced to a few convex pieces (Multiple Convex), then
-- pulled in by the crash dents.
--
-- The rest hulls are computed once per process from the body panels of the model (cached by the
-- decomposition module); a dent only moves their vertices, so rebuilding after a crash costs a
-- few hundred offsetAt calls and no new decomposition.
local Models = require('source.engine.import.models')
local Decomposition = require('source.engine.physics.3d.decomposition')
local Hull = require('source.engine.physics.3d.decomposition.hull')

local CarHull = {}

CarHull.PATH = 'scene://models/duke69.glb'
-- Panels that make up the solid body. Glass, interior, wheels and suspension add no useful volume.
local PANELS = { Body = true, Hood = true, Trunkdoor = true }
CarHull.options = { maxHulls = 6, hullPoints = 24, concavity = 0.03, resolution = 28 }

local restHulls

-- Hulls of the undamaged body in model space (origin on the ground below the chassis centre).
function CarHull.rest(resources)
    if restHulls then
        return restHulls
    end
    local asset = Models.load(CarHull.PATH, resources)
    local soup = {}
    for _, part in ipairs(asset.parts) do
        if PANELS[part.node.name] then
            for _, v in ipairs(part.geometry.vertices) do
                soup[#soup + 1] = { v[1], v[2], v[3] }
            end
        end
    end
    restHulls = Decomposition.decompose(soup, CarHull.options)
    return restHulls
end

-- Point lists in chassis space, one per hull piece. `lift` is the model origin's distance below
-- the chassis centre; `floor` the lowest allowed chassis-space height (the underside is flattened
-- there so a dent never drags a hull under the wheels' ground clearance).
function CarHull.pieces(hulls, dents, lift, floor)
    local pieces = {}
    for _, hull in ipairs(hulls) do
        local points = {}
        for i, v in ipairs(hull) do
            local x, y, z = v[1], v[2], v[3]
            if dents then
                local ox, oy, oz = dents:offsetAt(x, y, z)
                x, y, z = x + ox, y + oy, z + oz
            end
            points[i] = { x, math.max(y - lift, floor), z }
        end
        -- A dent can flatten a thin piece completely; keep its rest shape then.
        if Hull.classify(points) ~= 'solid' then
            for i, v in ipairs(hull) do
                points[i] = { v[1], math.max(v[2] - lift, floor), v[3] }
            end
        end
        pieces[#pieces + 1] = points
    end
    return pieces
end

return CarHull
