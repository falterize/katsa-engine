-- Rope/spring impulses are engine policy shared by both simulation adapters.
local M = require('source.engine.math.math3d')
local Inputs = require('./inputs')

local Distance = {}

function Distance.rememberAnchors(self, a, b)
    self._previousAnchor0, self._previousAnchor1 =
        self._previousAnchor0 or {}, self._previousAnchor1 or {}
    for i = 1, 3 do
        self._previousAnchor0[i], self._previousAnchor1[i] = a[i], b[i]
    end
end

local function anchorMotion(body, localPosition, old, dt, direction)
    if not old then
        return 0
    end
    local x, y, z = M.transform(
        body.object:getWorldMatrix(),
        (localPosition[1] - old[1]) / dt,
        (localPosition[2] - old[2]) / dt,
        (localPosition[3] - old[3]) / dt,
        0
    )
    return x * direction[1] + y * direction[2] + z * direction[3]
end

function Distance.step(self, a, b, p0, p1, m0, m1, dt)
    local inputs = Inputs.begin(self, a, b, 'distance')
    inputs:value(self.allowCollision)
    inputs:vector(p0)
    inputs:vector(p1)
    local linkKey = inputs:finish()
    if self._distanceLinkKey ~= linkKey then
        local O = self._world.physics.valueTypes
        local config = O.GenericJointConfig.new()
        for i = 0, 2 do
            config.translationalLimitMotors[i]:setLimits(1, 0)
            config.rotationalLimitMotors[i]:setLimits(1, 0)
        end
        local candidate = self._world.physics:_createJoint('Generic', a, b, {
            anchor1 = p0,
            anchor2 = p1,
            allowCollision = self.allowCollision == true,
            translationalLimitMotors = config.translationalLimitMotors,
            rotationalLimitMotors = config.rotationalLimitMotors,
        })
        self:releaseJoint(true)
        self.joint = candidate
        self._distanceLinkKey = linkKey
    end
    self.status = 'Active'
    local dx, dy, dz = m1[4] - m0[4], m1[8] - m0[8], m1[12] - m0[12]
    local distance = math.sqrt(dx * dx + dy * dy + dz * dz)
    if distance < 1e-6 or self.kind == 'Rope' and distance < self.length then
        Distance.rememberAnchors(self, p0, p1)
        return
    end
    dx, dy, dz = dx / distance, dy / distance, dz / distance
    self._direction, self._point0, self._point1 =
        self._direction or {}, self._point0 or {}, self._point1 or {}
    local direction, point0, point1 = self._direction, self._point0, self._point1
    direction[1], direction[2], direction[3] = dx, dy, dz
    point0[1], point0[2], point0[3] = m0[4], m0[8], m0[12]
    point1[1], point1[2], point1[3] = m1[4], m1[8], m1[12]
    local speedA, invA = a:pointResponse(point0, direction)
    local speedB, invB = b:pointResponse(point1, direction)
    speedA = speedA + anchorMotion(a, p0, self._previousAnchor0, dt, direction)
    speedB = speedB + anchorMotion(b, p1, self._previousAnchor1, dt, direction)
    Distance.rememberAnchors(self, p0, p1)
    local speed = speedB - speedA
    if invA + invB == 0 then
        return
    end
    local impulse
    if self.kind == 'Spring' then
        local factor = dt * (self.damping + dt * self.stiffness)
        impulse = (dt * self.stiffness * (distance - self.length) + factor * speed)
            / (1 + (invA + invB) * factor)
    else
        impulse =
            math.max(0, (speed + math.max(0, distance - self.length) * 0.2 / dt) / (invA + invB))
    end
    if self.breakForce > 0 and math.abs(impulse) / dt > self.breakForce then
        self.enabled = false
        self.status = 'Broken'
        self:emit('Broken', self)
        return
    end
    self._impulse = self._impulse or {}
    local v = self._impulse
    v[1], v[2], v[3] = dx * impulse, dy * impulse, dz * impulse
    if invA > 0 then
        a:applyImpulseAt(v, point0)
    end
    if invB > 0 then
        v[1], v[2], v[3] = -v[1], -v[2], -v[3]
        b:applyImpulseAt(v, point1)
    end
end

return Distance
