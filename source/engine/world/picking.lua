local Layering = require('../components.layering')
local ipairs = require('../math.array').ipairs
local pairs = require('../math.array').pairs
local M = require('../math.math3d')

local Picking = {}

function Picking.raycast(world, camera, x, y)
    if not world or not camera or camera.destroyed then
        return
    end
    local p, d = camera:screenRay(x, y)
    local nearest, depth
    local a, b, c = {}, {}, {}
    for _, o in ipairs(world.objects) do
        world:updateObject(o, true)
        if
            not o.destroyed
            and o:isVisible()
            and o.canQuery ~= false
            and o:getEffectiveOpacity() > 0
            and (o.color[4] or 1) > 0
            and Layering.sees(camera, o)
        then
            local vertices, m = o.geometry.vertices, o.combined or o.matrix
            for i = 1, #vertices, 3 do
                for j, v in ipairs({ a, b, c }) do
                    local q = vertices[i + j - 1]
                    v[1], v[2], v[3] = M.transform(m, q[1], q[2], q[3])
                end
                local t = M.rayTriangle(p[1], p[2], p[3], d[1], d[2], d[3], a, b, c)
                if t and t > 0 and (not depth or t < depth) then
                    nearest, depth = o, t
                end
            end
        end
    end
    return nearest, depth
end

function Picking.detector(world, camera, x, y)
    if not world.clickDetectors or not next(world.clickDetectors) then
        return
    end
    local object = Picking.raycast(world, camera, x, y)
    if not object then
        return
    end
    for detector in pairs(world.clickDetectors) do
        if detector:getTarget() == object and detector:canActivate() then
            return detector
        end
    end
end

return Picking
