-- Convex hulls, hull simplification and convex decomposition of triangle meshes, in plain Lua.
-- They back the "Simplified Convex" and "Multiple Convex" collision levels of Collider3D.
--
--     Decomposition.hull(points)                    exact hull (see hull.lua)
--     Decomposition.simplify(points, maxPoints)     one reduced convex hull
--     Decomposition.decompose(soup, options)        list of convex hulls, cached
--
-- Triangle soups are lists of { x, y, z } with three entries per triangle.
local Cache = require('./cache')
local Decompose = require('./decompose')
local Hull = require('./hull')

local Decomposition = {
    hull = Hull.compute,
    simplify = Decompose.simplify,
    defaults = Decompose.defaults,
    cache = Cache,
}

-- Like Decompose.run, but identical inputs return the same (shared, read-only) result.
function Decomposition.decompose(soup, options)
    options = options or {}
    local key = table.concat({
        Cache.fingerprint(soup),
        options.resolution or Decompose.defaults.resolution,
        options.maxHulls or Decompose.defaults.maxHulls,
        options.concavity or Decompose.defaults.concavity,
        options.hullPoints or Decompose.defaults.hullPoints,
    }, '|')
    local cached = Cache.get(key)
    if cached then
        return cached.hulls, cached.stats
    end
    local hulls, stats = Decompose.run(soup, options)
    Cache.put(key, { hulls = hulls, stats = stats })
    return hulls, stats
end

return Decomposition
