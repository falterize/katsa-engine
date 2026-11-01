local Drawing = {}

local function shape(fixture, body, mode, factor)
    local g, collider = katsa.graphics, fixture:getShape()
    local kind = collider:getType()
    if kind == 'circle' then
        local x, y = collider:getPoint()
        g.circle(mode, x / factor, y / factor, collider:getRadius() / factor)
    else
        local data = fixture:getUserData()
        local points = data._drawPoints
        if not points then
            points = { collider:getPoints() }
            for i = 1, #points do
                points[i] = points[i] / factor
            end
            data._drawPoints = points
        end
        if kind == 'polygon' then
            g.polygon(mode, points)
        else
            g.line(points)
        end
    end
end

function Drawing.draw(self, camera)
    -- Physics has no material pass. World2D renders authored UI descendants.
end

function Drawing.debug(self)
    if self.released or not self.debug.enabled then
        return
    end
    local g, f = katsa.graphics, self.factor
    g.push('all')
    g.setShader()
    g.setDepthMode()
    g.setLineWidth(1)
    for _, body in ipairs(self.bodies) do
        g.push()
        -- Debug geometry follows the exact solver pose, independent of visual interpolation.
        local x, y = body:getPosition()
        g.translate(x, y)
        g.rotate(body.raw:getAngle())
        if body.object.isTrigger then
            g.setColor(1, 0.65, 0.2)
        elseif body.type == 'Static' then
            g.setColor(0.45, 0.65, 1)
        elseif body:isSleeping() then
            g.setColor(0.6, 0.6, 0.6)
        else
            g.setColor(0.25, 1, 0.65)
        end
        if self.debug.shapes then
            for _, fixture in ipairs(body.fixtures) do
                shape(fixture, body, 'line', f)
            end
        end
        if self.debug.centers then
            g.line(-4, 0, 4, 0)
            g.line(0, -4, 0, 4)
        end
        g.pop()
        if self.debug.velocities then
            local vx, vy = body:getLinearVelocity()
            g.line(x, y, x + vx * 0.15, y + vy * 0.15)
        end
    end
    if self.debug.joints then
        g.setColor(1, 0.8, 0.2)
        for _, constraint in ipairs(self.constraints) do
            local joint = constraint.joint
            if joint and not joint:isDestroyed() then
                local x0, y0, x1, y1 = joint:getAnchors()
                if x0 and x1 then
                    g.line(x0 / f, y0 / f, x1 / f, y1 / f)
                end
            end
        end
    end
    if self.debug.contacts then
        g.setColor(1, 0.25, 0.3)
        for _, contact in ipairs(self.world:getContacts()) do
            if contact:isTouching() then
                local x, y = contact:getPositions()
                if x then
                    local nx, ny = contact:getNormal()
                    g.circle('fill', x / f, y / f, 2)
                    g.line(x / f, y / f, x / f + nx * 12, y / f + ny * 12)
                end
            end
        end
    end
    g.pop()
end

return Drawing
