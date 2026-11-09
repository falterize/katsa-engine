-- NavMesh: polygons from cells, funnel paths, dynamic obstacles and crowd steering.
local NavMesh = require('source.plugins.pathfinding.navmesh')

local Tests = {}

local function near(a, b, tolerance)
    return math.abs(a - b) <= (tolerance or 1e-3)
end

-- A flat width x depth floor (cell size 1, origin 0,0); `walls` are { cx0, cz0, cx1, cz1 } cells.
local function floor(width, depth, walls, options)
    local mesh = NavMesh.new({
        width = width,
        depth = depth,
        cellSize = 1,
        origin = { 0, 0 },
        tile = (options or {}).tile or 8,
    })
    local blocked, heights = {}, {}
    for index = 1, width * depth do
        heights[index] = 0
    end
    for _, wall in ipairs(walls or {}) do
        for cz = wall[2], wall[4] do
            for cx = wall[1], wall[3] do
                blocked[(cz - 1) * width + cx] = true
            end
        end
    end
    mesh:load({ blocked }, { heights })
    return mesh
end

local function length(path)
    return path.length
end

function Tests.run(tester)
    local open = floor(16, 16, {})
    tester:check(open:polygonCount() == 4, 'An open floor merges into one polygon per tile')
    local straight = open:findPath({ 1.5, 0, 1.5 }, { 14.5, 0, 12.5 })
    tester:check(
        straight and #straight.points == 2 and near(length(straight), math.sqrt(13 ^ 2 + 11 ^ 2)),
        'A route across open ground is one straight segment'
    )

    -- A wall with a gap at the bottom: the route bends once around its end.
    local walled = floor(16, 16, { { 8, 1, 9, 12 } })
    local around = walled:findPath({ 3.5, 0, 3.5 }, { 13.5, 0, 3.5 })
    tester:check(
        around
            and #around.points == 4
            and near(around.points[2][1], 7) and near(around.points[2][3], 12)
            and near(around.points[3][1], 9) and near(around.points[3][3], 12),
        'A route around a wall hugs its two end corners'
    )
    tester:check(
        around.length < 2 * 8.5 + 2 + 5,
        'The funnel path is shorter than a path through cell centres'
    )

    local sealed = floor(16, 16, { { 8, 1, 9, 16 } })
    local none, reason = sealed:findPath({ 3.5, 0, 3.5 }, { 13.5, 0, 3.5 })
    tester:check(none == nil and reason == 'no route', 'A sealed wall gives no route')

    -- Obstacles reroute and removing one restores the short route.
    local before = open.revision
    local box = open:addObstacle({ kind = 'box', x = 8, z = 8, halfX = 1, halfZ = 6 })
    local detour = open:findPath({ 3.5, 0, 8.5 }, { 13.5, 0, 8.5 })
    tester:check(
        open.revision > before and detour and #detour.points >= 3 and detour.length > 10.5,
        'A dynamic obstacle reroutes paths'
    )
    open:moveObstacle(box, 8, 18)
    local moved = open:findPath({ 3.5, 0, 8.5 }, { 13.5, 0, 8.5 })
    tester:check(moved and #moved.points == 2, 'Moving an obstacle frees the old place')
    open:removeObstacle(box)
    tester:check(open:locate(8.5, 14.5, 0) ~= nil, 'Removing an obstacle restores the polygons')
    local rebuilt = 0
    for _ in pairs(open.polygons) do
        rebuilt = rebuilt + 1
    end
    tester:check(rebuilt == open:polygonCount() and open:polygonCount() == 4, 'Tiles merge back after removal')

    -- Two floors joined by a link.
    local stairs = NavMesh.new({ width = 8, depth = 4, cellSize = 1, origin = { 0, 0 }, levels = 2, tile = 8 })
    local blockedLow, heightLow, blockedHigh, heightHigh = {}, {}, {}, {}
    for cz = 1, 4 do
        for cx = 1, 8 do
            local index = (cz - 1) * 8 + cx
            heightLow[index] = 0
            if cx >= 6 then
                heightHigh[index] = 4
            end
        end
    end
    stairs:load({ blockedLow, blockedHigh }, { heightLow, heightHigh })
    stairs:link(1, 5.5, 2.5, 2, 6.5, 2.5)
    local up = stairs:findPath({ 0.5, 0, 2.5 }, { 7.5, 4, 2.5 })
    tester:check(
        up and up.levels[#up.levels] == 2 and near(up.points[#up.points][2], 4),
        'A link joins floors and the route ends on the upper one'
    )

    -- Crowd: two agents swap sides on one line without ever overlapping, and stop at the goal.
    local crowd = NavMesh.Crowd.new(floor(24, 12, {}))
    local a = crowd:add({ x = 2.5, y = 0, z = 6, radius = 0.5, maxSpeed = 4 })
    local b = crowd:add({ x = 21.5, y = 0, z = 6, radius = 0.5, maxSpeed = 4 })
    crowd:setTarget(a, 21.5, 0, 6)
    crowd:setTarget(b, 2.5, 0, 6)
    local closest = math.huge
    for _ = 1, 400 do
        crowd:update(1 / 30)
        closest = math.min(closest, math.sqrt((a.x - b.x) ^ 2 + (a.z - b.z) ^ 2))
    end
    tester:check(closest >= 0.9, 'Agents walking toward each other keep apart')
    tester:check(
        a.state == 'arrived' and b.state == 'arrived' and near(a.x, 21.5, 0.6) and near(b.x, 2.5, 0.6),
        'Agents reach opposite goals'
    )
    local lone = NavMesh.Crowd.new(floor(8, 8, {}))
    local walker = lone:add({ x = 1.5, y = 0, z = 1.5 })
    lone:setTarget(walker, 100, 0, 100)
    for _ = 1, 5 do
        lone:update(0.1)
    end
    tester:check(walker.state == 'failed' and walker.x < 8.1, 'A target off the mesh fails without leaving it')
end

return Tests
