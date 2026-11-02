-- Pathfinding debug view: the cells of every baked NavMap (one color per floor), the links
-- between floors and the most recent routes with their waypoints. Drawn after the 3D scene when
-- `Environment.debug.pathfinding.enabled` is on.
local Debug = {}

local FLOOR_COLORS = { { 0.2, 0.8, 0.4 }, { 0.3, 0.6, 1 }, { 1, 0.7, 0.2 }, { 0.9, 0.4, 0.9 } }

local function eachMap(world, visit)
    for _, node in ipairs(world.root:getDescendants()) do
        if node.className == 'NavMap' or node.isA and node:isA('NavMap') then
            if node.baked and node.map then
                visit(node)
            end
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

function Debug.drawMap(map, camera, settings)
    local eye = camera.position or { 0, 0, 0 }
    local range2 = settings.drawDistance ^ 2
    local half = map.cellSize / 2 * 0.9
    for level, grid in ipairs(map.levels) do
        local color = FLOOR_COLORS[(level - 1) % #FLOOR_COLORS + 1]
        for cz = 1, map.height do
            for cx = 1, map.width do
                if not grid:isBlocked(cx, cz) then
                    local x, z = grid:toWorld(cx, cz)
                    local y = (map:heightAtCell(level, cx, cz) or 0) + 0.05
                    local dx, dz = x - eye[1], z - eye[3]
                    if dx * dx + dz * dz < range2 then
                        if settings.drawCells then
                            local a, b, c, d =
                                { x - half, y, z - half },
                                { x + half, y, z - half },
                                { x + half, y, z + half },
                                { x - half, y, z + half }
                            line(camera, a, b, color, 0.7)
                            line(camera, b, c, color, 0.7)
                            line(camera, c, d, color, 0.7)
                            line(camera, d, a, color, 0.7)
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
            local a = { x, (map:heightAtCell(level, cx, cz) or 0) + 0.1, z }
            for _, target in ipairs(targets) do
                local tl, tx, tz = map:decode(target[1])
                local bx, bz = map.levels[tl]:toWorld(tx, tz)
                line(camera, a, { bx, (map:heightAtCell(tl, tx, tz) or 0) + 0.1, bz }, { 1, 1, 1 }, 0.9)
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

function Debug.draw(world, camera, settings)
    katsa.graphics.push('all')
    katsa.graphics.setShader()
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
