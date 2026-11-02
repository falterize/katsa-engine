local Orientation = {}
local labels = { 'X', 'Y', 'Z' }
local colors = { { 1, 0.3, 0.3 }, { 0.3, 1, 0.45 }, { 0.35, 0.65, 1 } }

local function axis(x, y, dx, dy, index, depth, length)
    local g, color = katsa.graphics, colors[index]
    g.setColor(color)
    local tx, ty = x + dx * length, y + dy * length
    g.setColor(color[1], color[2], color[3], 0.3)
    g.line(x - dx * length * 0.4, y - dy * length * 0.4, x, y)
    g.setColor(color)
    g.line(x, y, tx, ty)
    if dx * dx + dy * dy < 0.01 then
        g.circle(depth and depth > 0 and 'line' or 'fill', x, y, 5)
        tx, ty = x + 6, y - 14
    else
        g.circle('fill', tx, ty, 3)
    end
    g.print(labels[index], tx + 5, ty - 7)
end

function Orientation.draw(scene)
    local settings = scene.world.debug
    local orientation2D = settings.orientation2D or scene.ui.debug and scene.ui.debug.orientation2D
    if not orientation2D and not settings.orientation3D then
        return
    end
    local g = katsa.graphics
    local w, h = g.getDimensions()
    local scale = require('../../core.displayDpi').uiScale()
    local length, gap = 42 * scale, 74 * scale
    g.push('all')
    g.origin()
    g.setShader()
    g.setDepthMode()
    g.setScissor()
    g.setStencilTest()
    g.setLineWidth(2 * scale)
    g.setFont(scene.ui:font(14))
    if orientation2D then
        local x = w / 2 - (settings.orientation3D and gap or 0)
        local angle = scene.ui.currentCamera and math.rad(scene.ui.currentCamera.rotation) or 0
        if scene.ui.currentCamera then
            local _, _, rotation = scene.ui.currentCamera:getWorldPose()
            angle = math.rad(rotation)
        end
        axis(x, h / 2, math.cos(angle), math.sin(angle), 1, nil, length)
        axis(x, h / 2, math.sin(angle), -math.cos(angle), 2, nil, length)
        g.setColor(1, 1, 1)
        g.print('2D', x - 10, h / 2 + length + 12)
    end
    if settings.orientation3D then
        local x = w / 2 + (orientation2D and gap or 0)
        local camera = scene.world.activeCamera
        for i = 1, 3 do
            local dx = camera and camera.right[i] or (i == 1 and 1 or 0)
            local dy = camera and -camera.up[i] or (i == 2 and -1 or 0)
            local depth = camera and camera.forward[i] or 1
            axis(x, h / 2, dx, dy, i, depth, length)
        end
        g.setColor(1, 1, 1)
        g.print(camera and '3D' or '3D (no camera)', x - 10, h / 2 + length + 12)
    end
    g.pop()
end

return Orientation
