local unpack = require('../math.array').unpack
local M = require('../math.math3d')
local Shapes = require('./3d.shapes')

local Sim = {}

local function range(e, value)
    return value[1] + (value[2] - value[1]) * e.random:random()
end

function Sim.spawn(e)
    local p = table.remove(e.pool) or {}
    if e._plane then
        require('./2d.shapes').sample(e, p)
    else
        Shapes.sample(e, p)
    end
    local dx, dy, dz = M.normalize(e.direction[1], e.direction[2], e.direction[3] or 0)
    if dx == 0 and dy == 0 and dz == 0 then
        dy = 1
    end
    local ax, ay, az = math.abs(dy) < 0.99 and 0 or 1, math.abs(dy) < 0.99 and 1 or 0, 0
    local rx, ry, rz = M.normalize(dy * az - dz * ay, dz * ax - dx * az, dx * ay - dy * ax)
    local ux, uy, uz = dy * rz - dz * ry, dz * rx - dx * rz, dx * ry - dy * rx
    local cos = 1 - e.random:random() * (1 - math.cos(math.rad(e.spread)))
    local sin = math.sqrt(1 - cos * cos)
    local a = e.random:random() * math.pi * 2
    local speed = range(e, e.speed)
    local c, s = math.cos(a) * sin, math.sin(a) * sin
    p.vx, p.vy, p.vz =
        (dx * cos + rx * c + ux * s) * speed,
        (dy * cos + ry * c + uy * s) * speed,
        (dz * cos + rz * c + uz * s) * speed
    if e._plane then
        local angle = math.atan2(dy, dx) + math.rad((e.random:random() * 2 - 1) * e.spread)
        p.vx, p.vy, p.vz = math.cos(angle) * speed, math.sin(angle) * speed, 0
    end
    p.space = e.simulationSpace -- Existing particles keep their space when the property changes.
    if p.space == 'World' then
        local m = e:getWorldMatrix()
        p.x, p.y, p.z = M.transform(m, p.x, p.y, p.z)
        p.vx, p.vy, p.vz = M.transform(m, p.vx, p.vy, p.vz, 0)
    end
    p.collisionX, p.collisionY, p.collisionZ = nil, nil, nil
    p.age, p.life = 0, range(e, e.lifetime)
    p.size = range(e, e.startSize)
    p.rotation, p.angular = math.rad(range(e, e.startRotation)), math.rad(range(e, e.angularSpeed))
    e.particles[#e.particles + 1] = p
end

function Sim.step(system, e, dt)
    if not e._collisionFilter then
        e._collisionFilter = function(body, collider)
            local groups = system:physics().collisionGroups
            if system.dimension == 2 then
                local object = body.object
                local trigger = collider and collider.isTrigger
                if trigger == nil then
                    trigger = object.isTrigger
                end
                return object.canCollide ~= false
                    and not trigger
                    and groups:interacts(e.collisionGroup, object.collisionGroup or 'Default')
            end
            return body.canCollide
                and body.colliderEnabled ~= false
                and not body.isTrigger
                and groups:interacts(e.collisionGroup, body.group)
        end
    end
    if e._seed ~= e.seed then
        e:setSeed(e.seed)
    end
    local active = true
    local parent = e
    while parent do
        if parent.enabled == false then
            active = false
        end
        parent = parent.parent
    end
    if e.disabledBehavior == 'Clear' and not active then
        e:clear()
        return
    end
    if e._simulationPaused then
        return
    end
    local count = #e.particles
    local m = e:getWorldMatrix()
    local inverse
    local gravity = e.useWorldGravity and system:physics() and system:physics().gravity or e.gravity
    local gx, gy, gz =
        gravity[1] * e.gravityScale, gravity[2] * e.gravityScale, (gravity[3] or 0) * e.gravityScale
    local wind = system.wind
    local ax, ay, az = e.acceleration[1] + gx, e.acceleration[2] + gy, (e.acceleration[3] or 0) + gz
    local wx, wy, wz =
        wind[1] * e.windInfluence, wind[2] * e.windInfluence, (wind[3] or 0) * e.windInfluence
    local cursor = e._collisionCursor or 1
    e._collisionCursor = count > 0 and cursor % count + 1 or 1
    local order = e.particles
    local i = 1
    while i <= #order do
        local p = order[i]
        p.age = p.age + dt
        if p.age >= p.life then
            e.pool[#e.pool + 1] = p
            order[i] = order[#order]
            order[#order] = nil
        else
            local px, py, pz = p.x, p.y, p.z
            local vx, vy, vz = p.vx, p.vy, p.vz
            if p.space == 'Local' then
                inverse = inverse or require('../math.affine').inverse(m)
                px, py, pz = M.transform(m, px, py, pz)
                vx, vy, vz = M.transform(m, vx, vy, vz, 0)
            end
            local tx, ty, tz = ax, ay, az
            if e.attractionEnabled then
                local dx, dy, dz =
                    e.attractionPoint[1] - px,
                    e.attractionPoint[2] - py,
                    (e.attractionPoint[3] or 0) - pz
                local distance = math.sqrt(dx * dx + dy * dy + dz * dz)
                if distance > 1e-6 and distance <= e.attractionRange then
                    local force = e.attractionStrength
                        / (1 + (distance / e.attractionSoftening) ^ 2)
                        / distance
                    tx, ty, tz = tx + dx * force, ty + dy * force, tz + dz * force
                end
            end
            -- Exponential relaxation toward wind preserves stability with high drag.
            local damping = math.exp(-e.drag * dt)
            vx, vy, vz =
                (vx + tx * dt - wx) * damping + wx,
                (vy + ty * dt - wy) * damping + wy,
                (vz + tz * dt - wz) * damping + wz
            local nx, ny, nz = px + vx * dt, py + vy * dt, pz + vz * dt
            local hit
            local queryVisible = true
            if e.offscreenBehavior == 'Pause' then
                local visibility = system:visibility()
                local size = p.size
                    * require('../animation.sequence').evaluate(
                        e.lifetimeRamp.bindings.size,
                        p.age / p.life,
                        e.lifetimeRamp.interpolation
                    )
                queryVisible = visibility.point(
                    e,
                    system.visibilityCamera,
                    px,
                    py,
                    pz,
                    math.max(0, size)
                ) or visibility.point(
                    e,
                    system.visibilityCamera,
                    nx,
                    ny,
                    nz,
                    math.max(0, size)
                )
            end
            if e.collisionEnabled and not p.collisionX then
                p.collisionX, p.collisionY, p.collisionZ = px, py, pz
            end
            if
                e.collisionEnabled
                and queryVisible
                and system:physics()
                and system.stats.collisionQueries < system.collisionBudget
                and (i - cursor) % math.max(1, count) < system.collisionBudget
            then
                -- Sweep from the last tested position, not just this frame's
                -- start: particles may skip queries when the shared budget runs out.
                system.rayStart[1], system.rayStart[2], system.rayStart[3] =
                    p.collisionX, p.collisionY, p.collisionZ
                system.rayEnd[1], system.rayEnd[2], system.rayEnd[3] = nx, ny, nz
                if
                    (nx - p.collisionX) ^ 2 + (ny - p.collisionY) ^ 2 + (nz - p.collisionZ) ^ 2
                    > 1e-10
                then
                    system.stats.collisionQueries = system.stats.collisionQueries + 1
                    hit = system
                        :physics()
                        :raycast(system.rayStart, system.rayEnd, e._collisionFilter, system.hit)
                    p.collisionX, p.collisionY, p.collisionZ = nx, ny, nz
                end
            end
            if hit then
                if e.collisionResponse == 'Kill' then
                    p.age = p.life
                else
                    local n = hit.normal
                    nx, ny, nz =
                        hit.position[1] + n[1] * 0.02,
                        hit.position[2] + n[2] * 0.02,
                        (hit.position[3] or 0) + (n[3] or 0) * 0.02
                    local dot = vx * n[1] + vy * n[2] + vz * (n[3] or 0)
                    local slide = 1 - e.collisionFriction
                    if dot < 0 then
                        vx, vy, vz =
                            (vx - dot * n[1]) * slide - dot * n[1] * e.restitution,
                            (vy - dot * n[2]) * slide - dot * n[2] * e.restitution,
                            (vz - dot * (n[3] or 0)) * slide - dot * (n[3] or 0) * e.restitution
                    end
                end
            end
            if hit then
                p.collisionX, p.collisionY, p.collisionZ = nx, ny, nz
            end
            if not e.collisionEnabled then
                p.collisionX, p.collisionY, p.collisionZ = nil, nil, nil
            elseif not queryVisible then
                -- Offscreen integration deliberately omits collisions; do not replay that path on
                -- return.
                p.collisionX, p.collisionY, p.collisionZ = nx, ny, nz
            end
            if p.space == 'Local' then
                nx, ny, nz = M.transform(inverse, nx, ny, nz)
                vx, vy, vz = M.transform(inverse, vx, vy, vz, 0)
            end
            p.x, p.y, p.z, p.vx, p.vy, p.vz = nx, ny, nz, vx, vy, vz
            p.rotation = p.rotation + p.angular * dt
            i = i + 1
        end
    end
    if active and not e._adorneeLost and e:isVisible() then
        e.emission = e.emission + e.rate * dt
        local emit = math.floor(e.emission)
        e.emission = e.emission - emit
        if emit > 0 then
            system:emit(e, emit)
        end
    end
    e.liveCount = #e.particles
end

return Sim
