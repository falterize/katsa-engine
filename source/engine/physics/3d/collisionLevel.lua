-- Collision levels of Geometry and Points colliders, named after Godot's collision shape types:
--
--   Trimesh            exact triangles (static bodies only)
--   Single Convex      one convex hull per mesh
--   Simplified Convex  one convex hull per mesh, few vertices
--   Multiple Convex    several convex hulls that follow the model, so it may be concave
--   Bounding Box       one box around the model
--
-- `kind` turns a level name into the short token the builders switch on: 'trimesh', 'convex',
-- 'simplified', 'multiple' or 'box'.
local Level = {}

-- The names shown in the inspector, in Godot's order.
Level.names = { 'Trimesh', 'Single Convex', 'Simplified Convex', 'Multiple Convex', 'Bounding Box' }

local kinds = {
    ['Trimesh'] = 'trimesh',
    ['Single Convex'] = 'convex',
    ['Simplified Convex'] = 'simplified',
    ['Multiple Convex'] = 'multiple',
    ['Bounding Box'] = 'box',
}

function Level.kind(name)
    local kind = kinds[name]
    assert(
        kind,
        'Collision level must be Trimesh, Single Convex, Simplified Convex, Multiple Convex or '
            .. 'Bounding Box, got ' .. tostring(name)
    )
    return kind
end

-- True for the level that needs a Static body and exact triangles.
function Level.isTrimesh(name)
    return Level.kind(name) == 'trimesh'
end

return Level
