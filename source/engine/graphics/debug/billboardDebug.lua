local unpack = require('../../math.array').unpack
local ipairs = require('../../math.array').ipairs
local Math = require('../../math.math3d')
local Support = require('../../world.surfaces.support')

local Debug = {}

local function segment(camera, a, b, color)
    local ax, ay, az = Math.transform(camera.view, unpack(a))
    local bx, by, bz = Math.transform(camera.view, unpack(b))
    if az < (camera.nearClip or camera.near) and bz < (camera.nearClip or camera.near) then
        return
    end
    if az < (camera.nearClip or camera.near) then
        local t = ((camera.nearClip or camera.near) - az) / (bz - az)
        ax, ay, az = ax + (bx - ax) * t, ay + (by - ay) * t, (camera.nearClip or camera.near)
    end
    if bz < (camera.nearClip or camera.near) then
        local t = ((camera.nearClip or camera.near) - bz) / (az - bz)
        bx, by, bz = bx + (ax - bx) * t, by + (ay - by) * t, (camera.nearClip or camera.near)
    end
    katsa.graphics.setColor(unpack(color))
    local sax, say = camera:viewToScreen(ax, ay, az)
    local sbx, sby = camera:viewToScreen(bx, by, bz)
    katsa.graphics.line(sax, say, sbx, sby)
end

function Debug.draw(world, camera)
    local g = katsa.graphics
    for _, board in ipairs(world.billboards) do
        if board.debugEnabled and board.drawable and not board:isA('SurfaceUI') then
            g.push('all')
            g.setShader()
            g.setDepthMode()
            g.setLineWidth(2)
            local ref = Support.resolve(board)
            if ref then
                segment(
                    camera,
                    ref:getRenderWorldPosition(),
                    board.anchorWorldPosition,
                    { 1, 0.75, 0.1, 1 }
                )
                segment(
                    camera,
                    board.anchorWorldPosition,
                    { board.matrix[4], board.matrix[8], board.matrix[12] },
                    { 0.1, 1, 1, 1 }
                )
                local m = board.matrix
                local corners = {}
                for i, p in ipairs({ { -0.5, -0.5 }, { 0.5, -0.5 }, { 0.5, 0.5 }, { -0.5, 0.5 } }) do
                    corners[i] = { Math.transform(m, p[1], p[2], 0) }
                end
                for i = 1, 4 do
                    segment(camera, corners[i], corners[i % 4 + 1], { 1, 0.25, 0.7, 1 })
                end
                for axis = 1, 3 do
                    local length = axis == 3 and math.sqrt(m[1] ^ 2 + m[5] ^ 2 + m[9] ^ 2) * 0.3
                        or 0.2
                    local b = {
                        m[4] + m[axis] * length,
                        m[8] + m[4 + axis] * length,
                        m[12] + m[8 + axis] * length,
                    }
                    segment(
                        camera,
                        { m[4], m[8], m[12] },
                        b,
                        axis == 1 and { 1, 0.2, 0.2, 1 }
                            or axis == 2 and { 0.2, 1, 0.2, 1 }
                            or { 0.3, 0.5, 1, 1 }
                    )
                end
            end
            g.pop()
        end
    end
end

return Debug
