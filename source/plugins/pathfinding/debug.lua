-- Pathfinding debug views, drawn after the 3D scene. This module is the grid view: the cells of
-- every baked NavMap3D (one color per floor), the links between floors and the routes, shown while
-- `Environment.debug.pathfinding.enabled` is on; drawCells / drawLinks / drawPaths pick the parts.
local Debug = {}

local FLOOR_COLORS = { { 0.2, 0.8, 0.4 }, { 0.3, 0.6, 1 }, { 1, 0.7, 0.2 }, { 0.9, 0.4, 0.9 } }

local function eachMap(world, visit)
    -- NavMaps register themselves (see nodes/navMap3D.lua), so no tree walk per frame.
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

-- The per-cell facts the view needs (free flag, surface height) are extracted once per map
-- revision, so a frame only walks the cells near the camera with plain array reads. Corners are
-- projected once per frame and shared by neighbouring cells; no tables are created per frame.
local layouts = setmetatable({}, { __mode = 'k' })
local segment = { 0, 0, 0, 0 }
local frame = 0

local function revisionOf(map)
    local total = map.revision or 0
    for _, grid in ipairs(map.levels) do
        total = total + (grid.revision or 0)
    end
    return total
end

local function layoutOf(map)
    local revision = revisionOf(map)
    local layout = layouts[map]
    if layout and layout.revision == revision then
        return layout
    end
    layout = { revision = revision, levels = {} }
    local width, height = map.width, map.height
    for level, grid in ipairs(map.levels) do
        local free, heights, stamps, sx, sy = {}, {}, {}, {}, {}
        for cz = 1, height do
            for cx = 1, width do
                local i = (cz - 1) * width + cx
                free[i] = not grid:isBlocked(cx, cz)
                heights[i] = (map:heightAtCell(level, cx, cz) or 0) + 0.05
            end
        end
        layout.levels[level] = { free = free, heights = heights, stamps = stamps, sx = sx, sy = sy, ys = {} }
    end
    layouts[map] = layout
    return layout
end

-- Cells near the camera only; each free cell draws just its two near edges (plus far edges next
-- to blocked cells).
function Debug.drawMap(map, camera, settings)
    local eye = camera.position or { 0, 0, 0 }
    local size = map.cellSize
    local reach = math.ceil(settings.drawDistance / size)
    local cxEye, czEye = map:toCell(eye[1], eye[3])
    local width, height = map.width, map.height
    local x0, x1 = math.max(1, cxEye - reach), math.min(width, cxEye + reach)
    local z0, z1 = math.max(1, czEye - reach), math.min(height, czEye + reach)
    local range2 = settings.drawDistance ^ 2
    local layout = layoutOf(map)
    local view = camera.view
    local nearClip, far = camera.nearClip, camera.far
    local halfWidth, halfHeight = camera.width / 2, camera.height / 2
    local orthographic, scale, focal = camera.orthographic, camera.pixelsPerUnit, camera.focal
    local g = katsa.graphics
    local v1, v2, v3, v4, v5, v6, v7, v8, v9, v10, v11, v12 =
        view[1], view[2], view[3], view[4], view[5], view[6], view[7], view[8], view[9], view[10], view[11], view[12]
    frame = frame + 1
    for level, grid in ipairs(map.levels) do
        local color = FLOOR_COLORS[(level - 1) % #FLOOR_COLORS + 1]
        local data = layout.levels[level]
        local free, heights, stamps, sx, sy = data.free, data.heights, data.stamps, data.sx, data.sy
        local originX, originY = grid.originX, grid.originY
        local stride = width + 2
        -- Screen position of cell corner (ix, iz) at height y, cached for this frame.
        local function corner(ix, iz, y)
            local key = iz * stride + ix
            if stamps[key] ~= frame then
                stamps[key] = frame
                local wx = originX + (ix - 1) * size
                local wz = originY + (iz - 1) * size
                local x = v1 * wx + v2 * y + v3 * wz + v4
                local vy = v5 * wx + v6 * y + v7 * wz + v8
                local z = v9 * wx + v10 * y + v11 * wz + v12
                if z < nearClip or z > far then
                    sx[key] = false
                elseif orthographic then
                    sx[key], sy[key] = halfWidth + x * scale, halfHeight - vy * scale
                else
                    sx[key], sy[key] = halfWidth + x * focal / z, halfHeight - vy * focal / z
                end
            end
            return sx[key], sy[key]
        end
        local function edge(ax, ay, bx, by, alpha)
            if ax and bx then
                g.setColor(color[1], color[2], color[3], alpha)
                segment[1], segment[2], segment[3], segment[4] = ax, ay, bx, by
                g.line(segment)
            end
        end
        if settings.drawCells then
            -- Neighbouring cells share edges on one straight line, so a run of free cells at the
            -- same height is a single segment: sweeps along rows (near and far edges) and along
            -- columns (left and right edges) replace four short segments per cell.
            local ys = data.ys
            for cz = z0, z1 do
                local row = (cz - 1) * width
                local dz = originY + (cz - 0.5) * size - eye[3]
                for cx = x0, x1 do
                    local i = row + cx
                    local dx = originX + (cx - 0.5) * size - eye[1]
                    ys[i] = free[i] and dx * dx + dz * dz < range2 and heights[i] or false
                end
            end
            local function qualifies(cx, cz, horizontal, far)
                local i = (cz - 1) * width + cx
                local y = ys[i]
                if y and far then
                    if horizontal then
                        if cz < height and free[i + width] then
                            return nil
                        end
                    elseif cx < width and free[i + 1] then
                        return nil
                    end
                end
                return y or nil
            end
            local function sweep(horizontal, far)
                local outerFrom, outerTo = horizontal and z0 or x0, horizontal and z1 or x1
                local innerFrom, innerTo = horizontal and x0 or z0, horizontal and x1 or z1
                local alpha = far and 0.9 or 0.7
                for outer = outerFrom, outerTo do
                    local start, runY
                    for inner = innerFrom, innerTo + 1 do
                        local y
                        if inner <= innerTo then
                            if horizontal then
                                y = qualifies(inner, outer, true, far)
                            else
                                y = qualifies(outer, inner, false, far)
                            end
                        end
                        if start and y ~= runY then
                            local line = (far and outer + 1 or outer)
                            local ax, ay, bx, by
                            if horizontal then
                                ax, ay = corner(start, line, runY)
                                bx, by = corner(inner, line, runY)
                            else
                                ax, ay = corner(line, start, runY)
                                bx, by = corner(line, inner, runY)
                            end
                            if ax and bx then
                                edge(ax, ay, bx, by, alpha)
                            else
                                -- An end is behind the camera: draw the visible cells one by one.
                                for cell = start, inner - 1 do
                                    if horizontal then
                                        ax, ay = corner(cell, line, runY)
                                        bx, by = corner(cell + 1, line, runY)
                                    else
                                        ax, ay = corner(line, cell, runY)
                                        bx, by = corner(line, cell + 1, runY)
                                    end
                                    edge(ax, ay, bx, by, alpha)
                                end
                            end
                            start = nil
                        end
                        if y and not start then
                            start, runY = inner, y
                        end
                    end
                end
            end
            sweep(true, false)
            sweep(false, false)
            sweep(true, true)
            sweep(false, true)
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

-- The remaining route of every crowd agent (NavAgent3D): from the agent through the corners it has
-- not reached yet to its goal, one colour per agent.
local function crowdColor(index)
    local hue = (index * 0.618034) % 1
    return {
        0.5 + 0.5 * math.sin(hue * 6.2832),
        0.5 + 0.5 * math.sin(hue * 6.2832 + 2.0944),
        0.5 + 0.5 * math.sin(hue * 6.2832 + 4.1888),
    }
end

function Debug.drawAgents(node, camera)
    local crowd = node.crowd
    if not crowd then
        return
    end
    for index, agent in ipairs(crowd.agents) do
        local path = agent.path
        if path then
            local color = crowdColor(index)
            local previous = { agent.x, agent.y + 0.4, agent.z }
            for pointIndex = path.index or 1, #path.points do
                local point = path.points[pointIndex]
                local here = { point[1], point[2] + 0.4, point[3] }
                line(camera, previous, here, color, 0.9)
                local sx, sy = camera:project(here)
                if sx then
                    katsa.graphics.setColor(color[1], color[2], color[3], 0.9)
                    katsa.graphics.circle('fill', sx, sy, 3)
                end
                previous = here
            end
        end
    end
end

-- Action links of the NavMesh (jump, climb, door ...): an arc from the take-off to the landing,
-- coloured by action, grey while the link is disabled; links made by hand (NavLink3D) also get
-- their action's name. One-way links end in an arrowhead.
local ACTION_COLORS = { jump = { 1, 0.6, 0.15 }, climb = { 0.9, 0.35, 1 } }
local OTHER_ACTION = { 0.3, 0.9, 1 }

function Debug.drawActionLinks(node, camera, settings)
    local mesh = node.mesh
    if not mesh then
        return
    end
    local eye = camera.position or { 0, 0, 0 }
    local range2 = settings.drawDistance ^ 2
    local g = katsa.graphics
    for _, link in ipairs(mesh.links) do
        local ax, az = link.ax, link.az
        if (ax - eye[1]) ^ 2 + (az - eye[3]) ^ 2 < range2 then
            local ay = (mesh:heightAt(link.level, ax, az) or 0) + 0.15
            local by = (mesh:heightAt(link.toLevel, link.bx, link.bz) or 0) + 0.15
            local color = link.enabled and (ACTION_COLORS[link.action] or OTHER_ACTION) or { 0.5, 0.5, 0.5 }
            local lift = math.max(link.arcHeight or 0, 0.2)
            local previous = { ax, ay, az }
            for step = 1, 8 do
                local t = step / 8
                local here = {
                    ax + (link.bx - ax) * t,
                    ay + (by - ay) * t + 4 * lift * t * (1 - t),
                    az + (link.bz - az) * t,
                }
                line(camera, previous, here, color, 0.9)
                previous = here
            end
            if not link.bidirectional then
                local x, y = camera:project({ link.bx, by + 0.05, link.bz })
                if x then
                    g.setColor(color[1], color[2], color[3], 0.9)
                    g.circle('fill', x, y, 3)
                end
            end
            if not link.auto then
                local x, y = camera:project({ (ax + link.bx) / 2, (ay + by) / 2 + lift + 0.4, (az + link.bz) / 2 })
                if x then
                    g.setColor(color[1], color[2], color[3], 1)
                    g.print(link.action, x - 12, y - 6)
                end
            end
        end
    end
end

-- Routes reported by games (a server's bot, for example) drawn with the NavMap3D routes:
-- `route = { points = { {x, y, z}, ... }, goal = { x, y, z }, color = { r, g, b } }`, or nil to
-- remove it. Drawn while `Environment.debug.pathfinding.drawPaths` is on.
function Debug.setRoute(world, key, route)
    world.navRoutes = world.navRoutes or {}
    world.navRoutes[key] = route
end

function Debug.drawRoutes(world, camera)
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
    local grid = settings.drawCells or settings.drawLinks
    if settings.drawPaths ~= false then
        Debug.drawRoutes(world, camera)
    end
    eachMap(world, function(node)
        if grid then
            Debug.drawMap(node.map, camera, settings)
        end
        if settings.drawLinks then
            Debug.drawActionLinks(node, camera, settings)
        end
        if settings.drawPaths ~= false then
            Debug.drawPaths(node, camera)
            Debug.drawAgents(node, camera)
        end
    end)
    katsa.graphics.pop()
end

return Debug
