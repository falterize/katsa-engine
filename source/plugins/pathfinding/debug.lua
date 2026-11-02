-- Pathfinding debug view: the cells of every baked NavMap (one color per floor), the links
-- between floors and the most recent routes with their waypoints. Drawn after the 3D scene when
-- `Environment.debug.pathfinding.enabled` is on.
local Debug = {}

local FLOOR_COLORS = { { 0.2, 0.8, 0.4 }, { 0.3, 0.6, 1 }, { 1, 0.7, 0.2 }, { 0.9, 0.4, 0.9 } }

local function eachMap(world, visit)
    -- NavMaps register themselves (see nodes/navMap.lua), so no tree walk per frame.
    for _, node in ipairs(world.navMaps or {}) do
        if not node.destroyed and node.baked and node.map then
            visit(node)
        end
    end
end

local function line(camera, a, b, color, alpha)
    local ax, ay = camera:project(a)
    local bx, by = camera:project(b)
    if ax and bx then
        katsa.graphics.setColor(color[1], color[2], color[3], alpha)
        katsa.graphics.line(ax, ay, bx, by)
    end
end

-- Cells near the camera only; every corner is projected once and shared by its neighbours, and
-- each free cell draws just its two near edges (plus far edges next to blocked cells).
function Debug.drawMap(map, camera, settings)
    local eye = camera.position or { 0, 0, 0 }
    local size = map.cellSize
    local reach = math.ceil(settings.drawDistance / size)
    local cxEye, czEye = map:toCell(eye[1], eye[3])
    local x0, x1 = math.max(1, cxEye - reach), math.min(map.width, cxEye + reach)
    local z0, z1 = math.max(1, czEye - reach), math.min(map.height, czEye + reach)
    local range2 = settings.drawDistance ^ 2
    local stride = map.width + 2
    for level, grid in ipairs(map.levels) do
        local color = FLOOR_COLORS[(level - 1) % #FLOOR_COLORS + 1]
        local corners = {}
        local function corner(ix, iz, y)
            local key = iz * stride + ix
            local point = corners[key]
            if point == nil then
                local wx = grid.originX + (ix - 1) * size
                local wz = grid.originY + (iz - 1) * size
                local sx, sy = camera:project({ wx, y, wz })
                point = sx and { sx, sy } or false
                corners[key] = point
            end
            return point
        end
        local function edge(a, b, alpha)
            if a and b then
                katsa.graphics.setColor(color[1], color[2], color[3], alpha)
                katsa.graphics.line(a[1], a[2], b[1], b[2])
            end
        end
        if settings.drawCells then
            for cz = z0, z1 do
                for cx = x0, x1 do
                    if not grid:isBlocked(cx, cz) then
                        local x, z = grid:toWorld(cx, cz)
                        local dx, dz = x - eye[1], z - eye[3]
                        if dx * dx + dz * dz < range2 then
                            local y = (map:heightAtCell(level, cx, cz) or 0) + 0.05
                            local a, b, c, d =
                                corner(cx, cz, y), corner(cx + 1, cz, y), corner(cx, cz + 1, y), corner(cx + 1, cz + 1, y)
                            edge(a, b, 0.7)
                            edge(a, c, 0.7)
                            if grid:isBlocked(cx + 1, cz) then
                                edge(b, d, 0.9)
                            end
                            if grid:isBlocked(cx, cz + 1) then
                                edge(c, d, 0.9)
                            end
                        end
                    end
                end
            end
        end
    end
    if settings.drawLinks then
        for id, targets in pairs(map.portals) do
            local level, cx, cz = map:decode(id)
            local x, z = map.levels[level]:toWorld(cx, cz)
            if (x - eye[1]) ^ 2 + (z - eye[3]) ^ 2 < range2 then
                local a = { x, (map:heightAtCell(level, cx, cz) or 0) + 0.1, z }
                for _, target in ipairs(targets) do
                    local tl, tx, tz = map:decode(target[1])
                    local bx, bz = map.levels[tl]:toWorld(tx, tz)
                    line(camera, a, { bx, (map:heightAtCell(tl, tx, tz) or 0) + 0.1, bz }, { 1, 1, 1 }, 0.9)
                end
            end
        end
    end
end

function Debug.drawPaths(node, camera)
    for rank, path in ipairs(node.recent) do
        local alpha = 1 - (rank - 1) / (#node.recent + 1)
        for index, point in ipairs(path.points) do
            local here = { point[1], point[2] + 0.4, point[3] }
            local sx, sy = camera:project(here)
            if sx then
                katsa.graphics.setColor(1, 0.9, 0.2, alpha)
                katsa.graphics.circle('fill', sx, sy, index == 1 and 6 or 4)
            end
            local previous = path.points[index - 1]
            if previous then
                line(camera, { previous[1], previous[2] + 0.4, previous[3] }, here, { 1, 0.9, 0.2 }, alpha)
            end
        end
    end
end

-- Routes reported by games (a server's bot, for example) drawn with the NavMap routes:
-- `route = { points = { {x, y, z}, ... }, goal = { x, y, z }, color = { r, g, b } }`, or nil to
-- remove it. Only drawn while `Environment.debug.pathfinding` is enabled with `drawPaths`.
function Debug.setRoute(world, key, route)
    world.navRoutes = world.navRoutes or {}
    world.navRoutes[key] = route
end

local function drawRoutes(world, camera)
    for _, route in pairs(world.navRoutes or {}) do
        local color = route.color or { 1, 0.9, 0.2 }
        local previous
        for _, point in ipairs(route.points) do
            local here = { point[1], point[2] + 0.9, point[3] }
            local sx, sy = camera:project(here)
            if sx then
                katsa.graphics.setColor(color[1], color[2], color[3], 1)
                katsa.graphics.circle('fill', sx, sy, 4)
            end
            if previous then
                line(camera, previous, here, color, 1)
            end
            previous = here
        end
        local goal, goalColor = route.goal, route.goalColor or color
        if goal then
            local here = { goal[1], goal[2] + 0.9, goal[3] }
            local sx, sy = camera:project(here)
            if sx then
                katsa.graphics.setColor(goalColor[1], goalColor[2], goalColor[3], 1)
                katsa.graphics.circle('fill', sx, sy, 7)
            end
            if previous then
                line(camera, previous, here, goalColor, 1)
            end
        end
    end
end

function Debug.draw(world, camera, settings)
    katsa.graphics.push('all')
    katsa.graphics.setShader()
    if settings.drawPaths then
        drawRoutes(world, camera)
    end
    eachMap(world, function(node)
        if settings.drawCells or settings.drawLinks then
            Debug.drawMap(node.map, camera, settings)
        end
        if settings.drawPaths then
            Debug.drawPaths(node, camera)
        end
    end)
    katsa.graphics.pop()
end

return Debug
