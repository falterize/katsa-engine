local unpack = require('../math.array').unpack
local ipairs = require('../math.array').ipairs
-- Optional first/third-person follow rig; gameplay and debug cameras remain independent.
local Controller = {}
Controller.__index = Controller

local function factor(rate, dt)
    return rate <= 0 and 1 or 1 - math.exp(-rate * math.max(0, dt))
end

local function angle(a, b, t)
    return a + ((b - a + 180) % 360 - 180) * t
end

function Controller.new(camera, options)
    options = options or {}
    local initial = { rotation = camera:getLookRotation() }
    local self = setmetatable({
        camera = camera,
        target = options.target,
        mode = options.mode or 'ThirdPerson',
        distance = options.distance or 75,
        offset = options.offset or { 0, 2, 0 },
        sensitivity = options.sensitivity or 0.18,
        minPitch = options.minPitch or -80,
        maxPitch = options.maxPitch or 80,
        minYaw = options.minYaw,
        maxYaw = options.maxYaw,
        positionSmooth = options.positionSmooth or 12,
        rotationSmooth = options.rotationSmooth or 16,
        radius = options.radius or 2,
        pitch = initial.rotation[1],
        yaw = initial.rotation[2],
        physics = options.physics,
        filter = options.filter,
        enabled = true,
        position = {},
        hit = {},
    }, Controller)
    assert(
        self.mode == 'FirstPerson' or self.mode == 'ThirdPerson',
        'Camera3D mode must be firstPerson or thirdPerson'
    )
    camera._controller = self
    camera.followMode = self.mode
    camera.followTarget = self.target and self.target.name or ''
    camera.followDistance = self.distance
    camera.followSensitivity = self.sensitivity
    camera.followSmooth = self.positionSmooth
    camera.pitchMin = self.minPitch
    camera.pitchMax = self.maxPitch
    self._targetName = camera.followTarget
    return self
end

function Controller:look(dx, dy)
    self.sensitivity = self.camera.followSensitivity
    self.minPitch, self.maxPitch = self.camera.pitchMin, self.camera.pitchMax
    self.pitch =
        math.max(self.minPitch, math.min(self.maxPitch, self.pitch - dy * self.sensitivity))
    self.yaw = self.yaw + dx * self.sensitivity
    if self.minYaw then
        self.yaw = math.max(self.minYaw, self.yaw)
    end
    if self.maxYaw then
        self.yaw = math.min(self.maxYaw, self.yaw)
    end
end

function Controller:update(dt, snap)
    local camera = self.camera
    if camera.followMode == 'Free' then
        return
    end
    if self._targetName ~= camera.followTarget then
        self._targetName = camera.followTarget
        self.target = nil
        for _, node in ipairs(camera._world.root:getDescendants()) do
            if node.name == camera.followTarget and node.getWorldMatrix then
                self.target = node
                break
            end
        end
    end
    self.mode, self.distance, self.positionSmooth =
        camera.followMode, camera.followDistance, camera.followSmooth
    local target = self.target
    if not self.enabled or camera.destroyed or not target or target.destroyed then
        return
    end
    if snap then
        self.transition = nil
    end
    if self:updateTransition(dt) then
        return
    end
    assert(not camera.body, 'Follow cameras cannot own a rigid body')
    local rotation = snap and 1 or factor(self.rotationSmooth, dt)
    local current = { position = camera:getWorldPosition(), rotation = camera:getLookRotation() }
    local worldRotation = {
        angle(current.rotation[1], self.pitch, rotation),
        angle(current.rotation[2], self.yaw, rotation),
        current.rotation[3],
    }
    camera:setWorldTransform({ position = current.position, rotation = worldRotation })
    camera:update(camera.width or 640, camera.height or 360)
    local m = target:getRenderWorldMatrix()
    local o = self.offset
    local x, y, z = require('../math.math3d').transform(m, o[1], o[2], o[3])
    local distance = self.mode == 'ThirdPerson' and self.distance or 0
    local desired = {
        x - camera.forward[1] * distance,
        y - camera.forward[2] * distance,
        z - camera.forward[3] * distance,
    }
    local t = snap and 1 or factor(self.positionSmooth, dt)
    -- Desired and current positions must use the same world frame, even under an Attachment3D.
    for i = 1, 3 do
        self.position[i] = current.position[i] + (desired[i] - current.position[i]) * t
    end
    if distance > 0 then
        self:constrain(self.position, { x, y, z })
    end
    camera:setWorldTransform({ position = self.position, rotation = worldRotation })
    camera:update(camera.width or 640, camera.height or 360)
end
local probes = { { 0, 0 }, { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }

function Controller:constrain(position, origin)
    if not self.physics then
        return
    end
    local camera = self.camera
    local fraction = 1
    -- Inactive cameras may never have rendered; radius probes need a live basis.
    camera:update(camera.width or 640, camera.height or 360)
    self._rayStart, self._rayEnd = self._rayStart or {}, self._rayEnd or {}
    self._queryFilter = self._queryFilter
        or function(body)
            if body.isTrigger or not body.canCollide then
                return false
            end
            if self.filter then
                return self.filter(body)
            end
            local node = self.target
            while node do
                if node.body == body then
                    return false
                end
                node = node.parent
            end
            return true
        end
    for _, axis in ipairs(probes) do
        for i = 1, 3 do
            local shift = (camera.right[i] * axis[1] + camera.up[i] * axis[2]) * self.radius
            self._rayStart[i] = origin[i] + shift
            self._rayEnd[i] = position[i] + shift
        end
        local hit = self.physics:raycast(self._rayStart, self._rayEnd, self._queryFilter, self.hit)
        if hit then
            fraction = math.min(fraction, math.max(0, hit.fraction - 0.03))
        end
    end
    for i = 1, 3 do
        position[i] = origin[i] + (position[i] - origin[i]) * fraction
    end
end

function Controller:transitionTo(position, rotation, seconds)
    local current =
        { position = self.camera:getWorldPosition(), rotation = self.camera:getLookRotation() }
    self.transition = {
        from = current.position,
        rotation = current.rotation,
        to = { unpack(position) },
        targetRotation = { unpack(rotation) },
        duration = math.max(0.001, seconds or 0.25),
        time = 0,
    }
end

function Controller:updateTransition(dt)
    local t = self.transition
    if not t then
        return false
    end
    t.time = t.time + dt
    local a = math.min(1, t.time / t.duration)
    a = a * a * (3 - 2 * a)
    local p, r = {}, {}
    for i = 1, 3 do
        p[i] = t.from[i] + (t.to[i] - t.from[i]) * a
        r[i] = angle(t.rotation[i], t.targetRotation[i], a)
    end
    if self.mode == 'ThirdPerson' and self.target and not self.target.destroyed then
        local origin = {
            require('../math.math3d').transform(
                self.target:getRenderWorldMatrix(),
                unpack(self.offset)
            ),
        }
        self:constrain(p, origin)
    end
    self.camera:setWorldTransform({ position = p, rotation = r })
    if a >= 1 then
        self.transition = nil
    end
    return true
end

return Controller
