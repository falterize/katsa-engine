local ipairs = require('source.engine.math.array').ipairs
local pairs = require('source.engine.math.array').pairs
local M = require('source.engine.math.math3d')

local D = {}

function D.draw(world, camera)
    local active = world.debug and world.debug.bones or false
    for _, animator in ipairs(world.animators or {}) do
        if animator.debugEnabled or world.debug and world.debug.bones then
            active = true
            break
        end
    end
    if not active then
        return
    end
    local g = katsa.graphics
    g.push('all')
    g.setShader()
    g.setDepthMode()
    g.setLineWidth(2)
    for _, animator in ipairs(world.animators) do
        if animator.debugEnabled or world.debug and world.debug.bones then
            local root = animator.model.root:getRenderWorldMatrix()
            local points = {}
            for _, node in ipairs(animator.model.nodes) do
                if node.isBone then
                    local p = { M.transform(root, node.world[4], node.world[8], node.world[12]) }
                    local x, y = camera:project(p)
                    if x then
                        points[node] = { x, y }
                        g.setColor(1, 0.65, 0.15, 1)
                        g.circle('fill', x, y, 3)
                    end
                end
            end
            for node, p in pairs(points) do
                local parent = node.parent
                while parent and not parent.isBone do
                    parent = parent.parent
                end
                if points[parent] then
                    g.setColor(0.2, 1, 0.65, 1)
                    g.line(p[1], p[2], points[parent][1], points[parent][2])
                end
                if node.instance then
                    for _, child in ipairs(node.instance.children) do
                        if child:isA('Attachment3D') then
                            local x, y = camera:project(child:getWorldPosition())
                            if x then
                                g.setColor(1, 0.25, 1, 1)
                                g.line(p[1], p[2], x, y)
                                g.circle('line', x, y, 5)
                            end
                        end
                    end
                end
            end
        end
    end
    g.pop()
end

return D
