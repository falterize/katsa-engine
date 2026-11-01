local Order = require('source.engine.ui.layout.order')
local Plane = {}

-- Rendered affine transforms and pointer inversion share body interpolation.
function Plane.transform(node)
    local a, b, c, d, x, y = node:getWorldTransform()
    local owner = node
    while owner and not owner:isA('World2D') do
        local body = owner:isA('Body2D') and owner.body
        if body and body.physics.interpolate and body.type ~= 'Static' then
            local alpha = body.physics.interpolationAlpha
            local bx = body.previousX + (body.currentX - body.previousX) * alpha
            local by = body.previousY + (body.currentY - body.previousY) * alpha
            local delta = (body.currentAngle - body.previousAngle + math.pi) % (math.pi * 2)
                - math.pi
            local angle = body.previousAngle + delta * alpha
            local ox, oy, rotation = owner:getWorldPose()
            local co, si =
                math.cos(angle - math.rad(rotation)), math.sin(angle - math.rad(rotation))
            return co * a - si * b,
                si * a + co * b,
                co * c - si * d,
                si * c + co * d,
                bx + co * (x - ox) - si * (y - oy),
                by + si * (x - ox) + co * (y - oy)
        end
        owner = owner.parent
    end
    return a, b, c, d, x, y
end

function Plane.pose(node)
    local a, b, _, _, x, y = Plane.transform(node)
    return x, y, math.atan2(b, a)
end

function Plane.owner(node)
    while node and not node:isA('Node2D') and not node:isA('World2D') do
        node = node.parent
    end
    return node and node:isA('Node2D') and node or nil
end

function Plane.localPoint(ui, owner, x, y)
    x, y = ui:screenToWorld2D(x, y)
    local a, b, c, d, px, py = Plane.transform(owner)
    local determinant, dx, dy = a * d - b * c, x - px, y - py
    return (d * dx - c * dy) / determinant + owner.size[1] / 2,
        owner.size[2] / 2 - (-b * dx + a * dy) / determinant
end

local function opacity(node)
    local value = 1
    while node and not node:isA('World2D') do
        if node.visible == false then
            return 0
        end
        if node:isA('Node2D') and not node:isA('Collider2D') then
            value = value * (1 - math.max(0, math.min(1, node.transparency or 0)))
        end
        node = node.parent
    end
    return value
end

local function inView(ui, node)
    if not ui.currentCamera then
        return true
    end
    local x, y = Plane.pose(node)
    local cx, cy = ui.currentCamera:getWorldPose()
    return (x - cx) ^ 2 + (y - cy) ^ 2 <= ui.currentCamera.drawDistance ^ 2
end

local function surface(ui, node)
    local hasVisual, pixelated = false, false
    for _, child in ipairs(node.children) do
        hasVisual = hasVisual or child:isA('UINode')
        pixelated = pixelated or child:isA('ImageLabel') and child.pixelate == true
    end
    if not hasVisual or node.size[1] <= 0 or node.size[2] <= 0 then
        return
    end
    local g = love.graphics
    local projection = ui.currentCamera and ui.currentCamera:projectionScale(ui.height) or 1
    local limit = g.getSystemLimits().texturesize
    local a, b, c, d = Plane.transform(node)
    local trace, determinant = a * a + b * b + c * c + d * d, a * d - b * c
    local stretch = math.sqrt(
        (trace + math.sqrt(math.max(0, trace * trace - 4 * determinant * determinant))) / 2
    )
    -- Round raster density upward in eighth steps. Floating rotation error and
    -- moving bodies must not resize or rerasterize a cached surface every frame.
    local desired = math.ceil(ui.density * projection * stretch * 8 - 0.000001) / 8
    local density = math.min(math.max(0.125, desired), limit / node.size[1], limit / node.size[2])
    local w = math.max(1, math.ceil(node.size[1] * density))
    local h = math.max(1, math.ceil(node.size[2] * density))
    local cache = node._uiSurface or {}
    if not node._uiSurface then
        node._uiSurface = cache
        node:onDestroy(function()
            if cache.canvas then
                ui.resources:releaseOwned(cache.canvas)
                cache.canvas = nil
            end
        end)
    end
    if not cache.canvas or cache.width ~= w or cache.height ~= h then
        if cache.canvas then
            ui.resources:releaseOwned(cache.canvas)
        end
        cache.canvas = ui.resources:own(g.newCanvas(w, h, { dpiscale = 1 }))
        cache.width, cache.height, cache.revision, cache.filter = w, h, nil, nil
    end
    local filter = pixelated and 'nearest' or 'linear'
    if cache.filter ~= filter then
        cache.canvas:setFilter(filter, filter)
        cache.filter = filter
    end
    -- Cache local pixels, not body poses. Moving rigid bodies do not redraw text,
    -- clipping, images or gradients until their authored visual content changes.
    if cache.revision ~= ui.revision or ui.animated or cache.density ~= density then
        g.push('all')
        g.setCanvas({ cache.canvas, stencil = true })
        g.origin()
        g.setScissor()
        g.setStencilTest()
        g.setShader()
        g.setDepthMode()
        g.clear(0, 0, 0, 0, 0)
        g.scale(density)
        local oldDensity, level, stack = ui.density, ui._stencilLevel, ui._stencilStack
        ui.density, ui._stencilLevel, ui._stencilStack = density, 0, {}
        for _, child in ipairs(Order.get(node.children)) do
            ui:drawNode(child)
        end
        ui.density, ui._stencilLevel, ui._stencilStack = oldDensity, level, stack
        g.pop()
        cache.revision, cache.density = ui.revision, density
    end
    return cache.canvas, density
end

function Plane.draw(ui, list)
    local g = love.graphics
    for _, node in ipairs(list) do
        if node:isA('Node2D') then
            local alpha = opacity(node)
            if alpha > 0 then
                local canvas, density
                if inView(ui, node) then
                    canvas, density = surface(ui, node)
                end
                if canvas then
                    local a, b, c, d, x, y = Plane.transform(node)
                    local sx = math.sqrt(a * a + b * b)
                    local sy = (a * d - b * c) / sx
                    g.push('all')
                    g.setShader()
                    g.setBlendMode('alpha', 'premultiplied')
                    g.setColor(alpha, alpha, alpha, alpha)
                    g.translate(x, y)
                    g.rotate(math.atan2(b, a))
                    g.scale(sx, sy)
                    g.shear((a * c + b * d) / (sx * sx), 0)
                    g.draw(
                        canvas,
                        -node.size[1] / 2,
                        node.size[2] / 2,
                        0,
                        1 / density,
                        -1 / density
                    )
                    g.pop()
                end
                Plane.draw(ui, node.children)
            end
        elseif node:isA('Folder') then
            Plane.draw(ui, node.children)
        end
    end
end

function Plane.hit(ui, list, x, y, hit, allowDisabled)
    for i = #list, 1, -1 do
        local node = list[i]
        if node:isA('Node2D') or node:isA('Folder') then
            if
                (allowDisabled or node.enabled ~= false)
                and node.visible ~= false
                and opacity(node) > 0
            then
                local found = Plane.hit(ui, node.children, x, y, hit, allowDisabled)
                if found then
                    return found
                end
                if node:isA('Node2D') and inView(ui, node) then
                    local lx, ly = Plane.localPoint(ui, node, x, y)
                    -- Each spatial surface clips to its authored dimensions.
                    if lx >= 0 and ly >= 0 and lx <= node.size[1] and ly <= node.size[2] then
                        found = hit(node.children, lx, ly, 0, 0)
                        if found then
                            return found
                        end
                    end
                end
            end
        end
    end
end

return Plane
