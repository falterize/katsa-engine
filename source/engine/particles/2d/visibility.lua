local M = require('source.engine.math.math3d')
local Visibility = {}
function Visibility.point(e, camera, x, y, z, radius)
    local ui = e._plane
    local sx, sy = ui:worldToScreen2D(x, y)
    local padding = radius * (camera and camera:projectionScale(ui.height) or 1) * ui.scale
    if camera and e.maxDistance > 0 then
        local cx, cy = camera:getWorldPose()
        if (x - cx) ^ 2 + (y - cy) ^ 2 > (e.maxDistance + radius) ^ 2 then
            return false
        end
    end
    return sx + padding >= ui.offsetX
        and sy + padding >= ui.offsetY
        and sx - padding <= ui.offsetX + ui.width * ui.scale
        and sy - padding <= ui.offsetY + ui.height * ui.scale
end

function Visibility.relevant(e, camera, render)
    if not e:isVisible() or not e._plane:layerVisible(e) then
        return false
    end
    local m = render and e:getRenderWorldMatrix() or e:getWorldMatrix()
    local radius = math.max(e.shapeSize[1], e.shapeSize[2]) + e.startSize[2]
    if Visibility.point(e, camera, m[4], m[8], 0, radius) then
        return true
    end
    for _, p in ipairs(e.particles) do
        local x, y = p.x, p.y
        if p.space == 'Local' then
            x, y = M.transform(m, x, y, 0)
        end
        if Visibility.point(e, camera, x, y, 0, p.size) then
            return true
        end
    end
    return false
end
return Visibility
