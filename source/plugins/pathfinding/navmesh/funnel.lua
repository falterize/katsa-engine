-- String pulling (the "simple stupid funnel algorithm"): turns a corridor of portals into the
-- shortest path through it. Portals are { lx, lz, rx, rz, level } where "left" is the
-- counter-clockwise endpoint in the (x, z) plane; the first and last portals are the start and
-- goal points (left == right). A portal may carry `link` and `role` ('start' or 'end' of an
-- action link); the corner made from it keeps them.
local Funnel = {}

-- Twice the signed area of the triangle (a, b, c) in the convention of the algorithm: negative
-- when c lies counter-clockwise of the line a -> b.
local function area(ax, az, bx, bz, cx, cz)
    local ux, uz = bx - ax, bz - az
    local vx, vz = cx - ax, cz - az
    return vx * uz - ux * vz
end

-- Returns a list of { x, z, level } corners.
function Funnel.pull(portals)
    local count = #portals
    local first, last = portals[1], portals[count]
    local points = { { x = first.lx, z = first.lz, level = first.level } }
    if count == 1 then
        return points
    end
    local apexX, apexZ, apexLevel = first.lx, first.lz, first.level
    local leftX, leftZ, rightX, rightZ = first.lx, first.lz, first.rx, first.rz
    local apexIndex, leftIndex, rightIndex = 1, 1, 1
    local i = 2
    local guard = count * count + 8
    while i <= count and guard > 0 do
        guard = guard - 1
        local portal = portals[i]
        local restarted = false
        -- Tighten the right side.
        if area(apexX, apexZ, rightX, rightZ, portal.rx, portal.rz) <= 0 then
            if
                (apexX == rightX and apexZ == rightZ)
                or area(apexX, apexZ, leftX, leftZ, portal.rx, portal.rz) > 0
            then
                rightX, rightZ, rightIndex = portal.rx, portal.rz, i
            else
                -- The right side crossed the left: the left corner becomes the new apex.
                local corner = portals[leftIndex]
                points[#points + 1] = { x = leftX, z = leftZ, level = corner.level, link = corner.link, role = corner.role }
                apexX, apexZ, apexLevel, apexIndex = leftX, leftZ, corner.level, leftIndex
                leftX, leftZ, rightX, rightZ = apexX, apexZ, apexX, apexZ
                leftIndex, rightIndex = apexIndex, apexIndex
                i = apexIndex + 1
                restarted = true
            end
        end
        if not restarted then
            if area(apexX, apexZ, leftX, leftZ, portal.lx, portal.lz) >= 0 then
                if
                    (apexX == leftX and apexZ == leftZ)
                    or area(apexX, apexZ, rightX, rightZ, portal.lx, portal.lz) < 0
                then
                    leftX, leftZ, leftIndex = portal.lx, portal.lz, i
                else
                    local corner = portals[rightIndex]
                    points[#points + 1] = { x = rightX, z = rightZ, level = corner.level, link = corner.link, role = corner.role }
                    apexX, apexZ, apexLevel, apexIndex = rightX, rightZ, corner.level, rightIndex
                    leftX, leftZ, rightX, rightZ = apexX, apexZ, apexX, apexZ
                    leftIndex, rightIndex = apexIndex, apexIndex
                    i = apexIndex + 1
                    restarted = true
                end
            end
        end
        if not restarted then
            i = i + 1
        end
    end
    local tail = points[#points]
    if tail.x ~= last.lx or tail.z ~= last.lz then
        points[#points + 1] = { x = last.lx, z = last.lz, level = last.level }
    end
    return points
end

return Funnel
