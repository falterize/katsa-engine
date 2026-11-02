local unpack = require('../../math.array').unpack
local ipairs = require('../../math.array').ipairs
local M = require('../../math.math3d')

local Gizmos = {}
Gizmos.__index = Gizmos

function Gizmos.new()
    return setmetatable({ lines = {}, nextUpdate = 0 }, Gizmos)
end

function Gizmos:update(world, lights, time)
    local settings = world.lighting.debug.gizmos
    if not settings.enabled then
        return
    end
    if time < self.nextUpdate then
        return
    end
    self.nextUpdate = time + 1 / math.max(0.01, settings.updateHz)
    local lines = self.lines
    for i = #lines, 1, -1 do
        lines[i] = nil
    end

    local function line(l, a, b)
        lines[#lines + 1] = { a, b, l }
    end
    for _, l in ipairs(world.lights) do
        if
            l.type ~= 'DirectionalLight3D'
            and l.enabled
            and l.eligible
            and (not settings.activeOnly or l.selected)
        then
            local p = l.worldPosition or l.position
            if l.type == 'PointLight3D' then
                for plane = 1, 3 do
                    for i = 0, 7 do
                        local a, b = { p[1], p[2], p[3] }, { p[1], p[2], p[3] }
                        local u, v = plane, plane % 3 + 1
                        a[u] = a[u] + math.cos(i * math.pi / 4) * l.range
                        a[v] = a[v] + math.sin(i * math.pi / 4) * l.range
                        b[u] = b[u] + math.cos((i + 1) * math.pi / 4) * l.range
                        b[v] = b[v] + math.sin((i + 1) * math.pi / 4) * l.range
                        line(l, a, b)
                    end
                end
                for axis = 1, 3 do
                    local a, b = { unpack(p) }, { unpack(p) }
                    a[axis] = a[axis] - 2
                    b[axis] = b[axis] + 2
                    line(l, a, b)
                end
            else
                local pitch, yaw, roll =
                    math.rad(l.rotation[1]), math.rad(l.rotation[2]), math.rad(l.rotation[3])
                local x, y, z =
                    -math.sin(yaw) * math.cos(pitch),
                    -math.sin(pitch),
                    math.cos(yaw) * math.cos(pitch)
                local dx, dy, dz =
                    x * math.cos(roll) - y * math.sin(roll),
                    y * math.cos(roll) + x * math.sin(roll),
                    z
                local rx, ry, rz =
                    math.cos(yaw) * math.cos(roll), math.cos(yaw) * math.sin(roll), math.sin(yaw)
                local ux, uy, uz = dy * rz - dz * ry, dz * rx - dx * rz, dx * ry - dy * rx

                local function point(t)
                    local c, s = math.cos(t) * l.radius, math.sin(t) * l.radius
                    return {
                        p[1] + dx * l.range + rx * c + ux * s,
                        p[2] + dy * l.range + ry * c + uy * s,
                        p[3] + dz * l.range + rz * c + uz * s,
                    }
                end
                for i = 0, 7 do
                    line(l, point(i * math.pi / 4), point((i + 1) * math.pi / 4))
                end
                for i = 0, 3 do
                    line(l, { p[1], p[2], p[3] }, point(i * math.pi / 2))
                end
                line(
                    l,
                    { p[1], p[2], p[3] },
                    { p[1] + dx * l.range, p[2] + dy * l.range, p[3] + dz * l.range }
                )
                line(
                    l,
                    { p[1] - rx * 2, p[2] - ry * 2, p[3] - rz * 2 },
                    { p[1] + rx * 2, p[2] + ry * 2, p[3] + rz * 2 }
                )
                line(
                    l,
                    { p[1] - ux * 2, p[2] - uy * 2, p[3] - uz * 2 },
                    { p[1] + ux * 2, p[2] + uy * 2, p[3] + uz * 2 }
                )
            end
        end
    end
end

function Gizmos:draw(world, camera)
    local settings = world.lighting.debug.gizmos
    if not settings.enabled then
        return
    end
    local limit = settings.maxDistance > 0 and settings.maxDistance or camera.drawDistance
    katsa.graphics.setColor(1, 220 / 255, 70 / 255, 0.8)
    katsa.graphics.setLineWidth(1)
    for _, line in ipairs(self.lines) do
        if
            M.distanceSquared(
                line[3].worldPosition or line[3].position,
                (camera.worldPosition or camera.position)
            ) <= limit ^ 2
        then
            local ax, ay, az = M.transform(camera.view, unpack(line[1]))
            local bx, by, bz = M.transform(camera.view, unpack(line[2]))
            if az >= (camera.nearClip or camera.near) or bz >= (camera.nearClip or camera.near) then
                if az < (camera.nearClip or camera.near) then
                    local t = ((camera.nearClip or camera.near) - az) / (bz - az)
                    ax, ay, az =
                        ax + (bx - ax) * t, ay + (by - ay) * t, (camera.nearClip or camera.near)
                end
                if bz < (camera.nearClip or camera.near) then
                    local t = ((camera.nearClip or camera.near) - bz) / (az - bz)
                    bx, by, bz =
                        bx + (ax - bx) * t, by + (ay - by) * t, (camera.nearClip or camera.near)
                end
                local sax, say = camera:viewToScreen(ax, ay, az)
                local sbx, sby = camera:viewToScreen(bx, by, bz)
                katsa.graphics.line(sax, say, sbx, sby)
            end
        end
    end
end

return Gizmos
