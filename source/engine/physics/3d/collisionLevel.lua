-- Collision levels of Geometry and Points colliders, named after Godot's collision shape types:
--
--   Trimesh            exact triangles (static bodies only)       was "Detailed"
--   Single Convex      one convex hull per mesh                    was "Convex"
--   Simplified Convex  one convex hull per mesh, few vertices
--   Multiple Convex    several convex hulls that follow the model, so it may be concave
--   Bounding Box       one box around the model                    was "Simple"
--
-- The older names stay valid; `kind` reduces any spelling (case, spaces and underscores ignored)
-- to one of: 'trimesh', 'convex', 'simplified', 'multiple', 'box'.
local Level = {}

-- The names shown in the inspector, in Godot's order.
Level.names = { 'Trimesh', 'Single Convex', 'Simplified Convex', 'Multiple Convex', 'Bounding Box' }

local kinds = {
    trimesh = 'trimesh',
    detailed = 'trimesh',
    singleconvex = 'convex',
    convex = 'convex',
    simplifiedconvex = 'simplified',
    simplified = 'simplified',
    multipleconvex = 'multiple',
    multiple = 'multiple',
    boundingbox = 'box',
    simple = 'box',
    box = 'box',
}

function Level.kind(name)
    local key = tostring(name):lower():gsub('[%s_]', '')
    local kind = kinds[key]
    assert(kind, 'Collision level must be Trimesh, Single Convex, Simplified Convex, Multiple Convex or Bounding Box')
    return kind
end

-- True for the level that needs a Static body and exact triangles.
function Level.isTrimesh(name)
    return Level.kind(name) == 'trimesh'
end

return Level
