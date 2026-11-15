-- Car collisions: static obstacles and car-versus-car. Cars are two circles (front and rear).
-- Every response returns impact records for the deformation system:
--   { x, z = car-space point of contact, nx, nz = car-space push direction, speed = closing speed }
local Collision = {}

-- Obstacles: { kind = 'circle', x, z, radius } or { kind = 'box', x, z, halfX, halfZ } (axis aligned).
local function penetration(obstacle, cx, cz, radius)
    if obstacle.kind == 'circle' then
        local dx, dz = cx - obstacle.x, cz - obstacle.z
        local distance = math.sqrt(dx * dx + dz * dz)
        local overlap = obstacle.radius + radius - distance
        if overlap <= 0 then
            return
        end
        if distance < 1e-6 then
            return overlap, 1, 0
        end
        return overlap, dx / distance, dz / distance
    end
    local nearX = math.max(obstacle.x - obstacle.halfX, math.min(cx, obstacle.x + obstacle.halfX))
    local nearZ = math.max(obstacle.z - obstacle.halfZ, math.min(cz, obstacle.z + obstacle.halfZ))
    local dx, dz = cx - nearX, cz - nearZ
    local distance = math.sqrt(dx * dx + dz * dz)
    if distance >= radius then
        return
    end
    if distance < 1e-6 then
        -- Circle center inside the box: leave through the closest side.
        local left = cx - (obstacle.x - obstacle.halfX)
        local right = obstacle.x + obstacle.halfX - cx
        local back = cz - (obstacle.z - obstacle.halfZ)
        local front = obstacle.z + obstacle.halfZ - cz
        local best = math.min(left, right, back, front)
        if best == left then
            return radius + left, -1, 0
        elseif best == right then
            return radius + right, 1, 0
        elseif best == back then
            return radius + back, 0, -1
        end
        return radius + front, 0, 1
    end
    return radius - distance, dx / distance, dz / distance
end

local function circles(vehicle)
    local offset = vehicle.config.circleOffset
    return { { 0, offset }, { 0, -offset } }
end

local function respond(vehicle, nx, nz, overlap, restitution, impacts, hitX, hitZ)
    vehicle.x = vehicle.x + nx * overlap
    vehicle.z = vehicle.z + nz * overlap
    local fx, fz, rx, rz = vehicle:axes()
    local forward = vehicle.speed
    local sideways = vehicle.slide
    -- Velocity along the contact normal; only motion into the surface is removed.
    local vx = fx * forward + rx * sideways
    local vz = fz * forward + rz * sideways
    local into = -(vx * nx + vz * nz)
    if into > 0 then
        vx = vx + nx * into * (1 + restitution)
        vz = vz + nz * into * (1 + restitution)
        vehicle.speed = vx * fx + vz * fz
        vehicle.slide = vx * rx + vz * rz
        local lx, lz = vehicle:toLocal(hitX, hitZ)
        local px = nx * rx + nz * rz
        local pz = nx * fx + nz * fz
        impacts[#impacts + 1] = { x = lx, z = lz, nx = -px, nz = -pz, speed = into }
    end
end

-- Pushes the car out of every overlapping obstacle. Returns the list of impacts.
function Collision.resolveStatic(vehicle, obstacles, restitution)
    local impacts = {}
    for _ = 1, 2 do
        for _, circle in ipairs(circles(vehicle)) do
            local cx, cz = vehicle:toWorld(circle[1], circle[2])
            for _, obstacle in ipairs(obstacles) do
                local overlap, nx, nz = penetration(obstacle, cx, cz, vehicle.config.radius)
                if overlap then
                    respond(
                        vehicle,
                        nx,
                        nz,
                        overlap,
                        restitution or 0.25,
                        impacts,
                        cx - nx,
                        cz - nz
                    )
                    cx, cz = vehicle:toWorld(circle[1], circle[2])
                end
            end
        end
    end
    return impacts
end

-- Separates two cars and exchanges momentum along the contact normal. Returns impacts for each:
-- aImpacts, bImpacts.
function Collision.resolvePair(a, b, restitution)
    restitution = restitution or 0.35
    local aImpacts, bImpacts = {}, {}
    for _, ca in ipairs(circles(a)) do
        for _, cb in ipairs(circles(b)) do
            local ax, az = a:toWorld(ca[1], ca[2])
            local bx, bz = b:toWorld(cb[1], cb[2])
            local dx, dz = bx - ax, bz - az
            local distance = math.sqrt(dx * dx + dz * dz)
            local minimum = a.config.radius + b.config.radius
            if distance < minimum then
                local nx, nz = 1, 0
                if distance > 1e-6 then
                    nx, nz = dx / distance, dz / distance
                end
                local overlap = (minimum - distance) / 2
                local afx, afz, arx, arz = a:axes()
                local bfx, bfz, brx, brz = b:axes()
                local avx, avz = afx * a.speed + arx * a.slide, afz * a.speed + arz * a.slide
                local bvx, bvz = bfx * b.speed + brx * b.slide, bfz * b.speed + brz * b.slide
                local closing = (avx - bvx) * nx + (avz - bvz) * nz
                a.x, a.z = a.x - nx * overlap, a.z - nz * overlap
                b.x, b.z = b.x + nx * overlap, b.z + nz * overlap
                if closing > 0 then
                    local share = closing * (1 + restitution) / 2
                    avx, avz = avx - nx * share, avz - nz * share
                    bvx, bvz = bvx + nx * share, bvz + nz * share
                    a.speed, a.slide = avx * afx + avz * afz, avx * arx + avz * arz
                    b.speed, b.slide = bvx * bfx + bvz * bfz, bvx * brx + bvz * brz
                    local mx, mz = (ax + bx) / 2, (az + bz) / 2
                    local alx, alz = a:toLocal(mx, mz)
                    local blx, blz = b:toLocal(mx, mz)
                    local apx, apz = nx * arx + nz * arz, nx * afx + nz * afz
                    local bpx, bpz = -nx * brx - nz * brz, -nx * bfx - nz * bfz
                    aImpacts[#aImpacts + 1] =
                        { x = alx, z = alz, nx = -apx, nz = -apz, speed = closing }
                    bImpacts[#bImpacts + 1] =
                        { x = blx, z = blz, nx = -bpx, nz = -bpz, speed = closing }
                end
            end
        end
    end
    return aImpacts, bImpacts
end

return Collision
