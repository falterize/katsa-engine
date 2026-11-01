local Frustum = require('source.engine.cameras.frustum')
local unpack = require('source.engine.math.array').unpack
local pairs = require('source.engine.math.array').pairs
local M = require('source.engine.math.math3d')
local Node = require('source.engine.nodes')
local Affine = require('source.engine.math.affine')

local Camera3D = Node.getClass('Camera3D')
Camera3D.__index = Camera3D

function Camera3D.new(settings)
    settings = settings or {}
    local values = {
        _registeredClass = settings._registeredClass,
        position = settings.position or { 0, 0, 0 },
        rotation = settings.rotation or { 0, 0, 0 },
        scale = settings.scale or { 1, 1, 1 },
        inheritScale = settings.inheritScale ~= false,
        near = settings.near or 1,
        far = settings.far or 5000,
        drawDistance = settings.drawDistance or math.sqrt(60000),
        focalLength = settings.focalLength or 400,
        referenceHeight = settings.referenceHeight or 720,
        pitchLimit = settings.pitchLimit,
        layers = settings.layers or -1,
        followMode = settings.followMode or 'Free',
        followTarget = settings.followTarget or '',
        followDistance = settings.followDistance or 75,
        followSensitivity = settings.followSensitivity or 0.18,
        followSmooth = settings.followSmooth or 12,
        pitchMin = settings.pitchMin or -80,
        pitchMax = settings.pitchMax or 80,
        name = settings.name or 'Camera3D',
        view = M.identity(),
        projection = M.identity(),
        viewProjection = M.identity(),
        right = {},
        up = {},
        forward = {},
    }
    for key, value in pairs(settings) do
        if values[key] == nil then
            values[key] = value
        end
    end
    return Node.adopt(setmetatable(values, Camera3D), settings.className or 'Camera3D')
end

function Camera3D:update(width, height)
    local matrix = self:getRenderWorldMatrix()
    local state = self._cameraProjectionState
    if
        state
        and state[1] == self._renderRevision
        and state[2] == width
        and state[3] == height
        and state[4] == self.focalLength
        and state[5] == self.referenceHeight
        and state[6] == self.near
        and state[7] == self.far
    then
        return
    end
    self.width, self.height = width, height
    self.focal = self.focalLength * height / self.referenceHeight
    -- Camera3D projection uses a rigid frame; scale affects inherited offsets,
    -- never focal length. Reject a sheared basis rather than skew the view.
    self._cameraFrame = self._cameraFrame or M.identity()
    local m = Affine.withoutScale(matrix, self._cameraFrame)
    local r, u, f = self.right, self.up, self.forward
    self._viewPosition = self._viewPosition or {}
    local p = self._viewPosition
    p[1], p[2], p[3] = m[4], m[8], m[12]
    for i = 1, 3 do
        local row = (i - 1) * 4
        r[i], u[i], f[i] = m[row + 1], m[row + 2], m[row + 3]
    end
    local v = self.view
    self.worldPosition = p
    for j = 1, 3 do
        v[j] = r[j]
        v[4 + j] = u[j]
        v[8 + j] = f[j]
    end
    v[4] = -(r[1] * p[1] + r[2] * p[2] + r[3] * p[3])
    v[8] = -(u[1] * p[1] + u[2] * p[2] + u[3] * p[3])
    v[12] = -(f[1] * p[1] + f[2] * p[2] + f[3] * p[3])
    local n, far = self.near, self.far
    assert(n > 0 and far > n, 'Camera3D requires 0 < near < far')
    local q = self.projection
    for j = 1, 16 do
        q[j] = 0
    end
    q[1] = 2 * self.focal / width
    q[6] = -2 * self.focal / height
    q[11] = (far + n) / (far - n)
    q[12] = -2 * far * n / (far - n)
    q[15] = 1
    M.multiply(q, v, self.viewProjection)
    state = state or {}
    self._cameraProjectionState = state
    state[1], state[2], state[3] = self._renderRevision, width, height
    state[4], state[5], state[6], state[7] =
        self.focalLength, self.referenceHeight, self.near, self.far
end

function Camera3D:project(p)
    local x, y, z = M.transform(self.view, p[1], p[2], p[3])
    if z < self.near or z > self.far then
        return
    end
    return self.width / 2 + x * self.focal / z, self.height / 2 - y * self.focal / z, z
end

function Camera3D:visible(position, radius)
    self._visibilityState = Frustum.capture(self, self._visibilityState)
    return Frustum.visible(self._visibilityState, position, radius)
end

function Camera3D:getLookRotation()
    self:update(self.width or 640, self.height or 360)
    return {
        math.deg(math.asin(math.max(-1, math.min(1, self.forward[2])))),
        math.deg(math.atan2(self.forward[1], self.forward[3])),
        0,
    }
end

function Camera3D:look(dx, dy, sensitivity)
    self.rotation[2] = self.rotation[2] + dx * sensitivity
    self.rotation[1] = self.rotation[1] - dy * sensitivity
    if self.pitchLimit then
        self.rotation[1] = math.max(-self.pitchLimit, math.min(self.pitchLimit, self.rotation[1]))
    end
end

function Camera3D:move(x, z, y, dt, speed, verticalSpeed)
    local yaw = math.rad(self.rotation[2])
    local n = math.max(1, math.sqrt(x * x + z * z))
    x, z = x / n, z / n
    self.position[1] = self.position[1] + (x * math.cos(yaw) + z * math.sin(yaw)) * dt * speed
    self.position[3] = self.position[3] + (z * math.cos(yaw) - x * math.sin(yaw)) * dt * speed
    self.position[2] = self.position[2] + y * dt * (verticalSpeed or speed)
end
Frustum.defaultVisible = Camera3D.visible
return Camera3D
