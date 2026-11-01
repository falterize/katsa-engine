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
        -- Perspective uses fov (vertical degrees); Orthographic uses orthoSize (half the
        -- visible height in world units). focalLength remains the legacy perspective input.
        projectionMode = settings.projectionMode or 'Perspective',
        orthoSize = settings.orthoSize or 10,
        -- Orthographic clip start along the view direction. nil places it behind the camera
        -- (at -far) so a tilted camera never slices away nearby ground; near is perspective-only.
        orthoNear = settings.orthoNear,
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
    if settings.fov == nil then
        values.fov = Camera3D.fovFromFocal(values.focalLength, values.referenceHeight)
    else
        values.focalLength = Camera3D.focalFromFov(settings.fov, values.referenceHeight)
    end
    values._syncedFov, values._syncedFocal = values.fov, values.focalLength
    return Node.adopt(setmetatable(values, Camera3D), settings.className or 'Camera3D')
end

function Camera3D.focalFromFov(fov, referenceHeight)
    assert(
        type(fov) == 'number' and fov > 0 and fov < 180,
        'Camera3D fov must be between 0 and 180 degrees'
    )
    return referenceHeight / (2 * math.tan(math.rad(fov) / 2))
end

function Camera3D.fovFromFocal(focalLength, referenceHeight)
    assert(focalLength > 0, 'Camera3D focalLength must be positive')
    return math.deg(2 * math.atan(referenceHeight / (2 * focalLength)))
end

-- fov and focalLength describe the same lens. The most recently edited one wins, so legacy
-- scenes that assign focalLength and new scenes that assign fov both keep working.
function Camera3D:syncLens()
    if self.fov ~= self._syncedFov then
        self.focalLength = Camera3D.focalFromFov(self.fov, self.referenceHeight)
    elseif self.focalLength ~= self._syncedFocal then
        self.fov = Camera3D.fovFromFocal(self.focalLength, self.referenceHeight)
    end
    self._syncedFov, self._syncedFocal = self.fov, self.focalLength
end

function Camera3D:isOrthographic()
    return self.projectionMode == 'Orthographic'
end

function Camera3D:update(width, height)
    local matrix = self:getRenderWorldMatrix()
    self:syncLens()
    assert(
        self.projectionMode == 'Perspective' or self.projectionMode == 'Orthographic',
        'Camera3D projectionMode must be Perspective or Orthographic'
    )
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
        and state[8] == self.projectionMode
        and state[9] == self.orthoSize
        and state[10] == self.orthoNear
    then
        return
    end
    self.width, self.height = width, height
    self.orthographic = self.projectionMode == 'Orthographic'
    assert(self.orthoSize > 0, 'Camera3D orthoSize must be positive')
    -- Pixels per world unit at depth z is focal / z for perspective, and constant for
    -- orthographic cameras. focal stays defined for both so legacy readers keep working.
    self.focal = self.focalLength * height / self.referenceHeight
    self.pixelsPerUnit = height / (2 * self.orthoSize)
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
    local far = self.far
    local n = self.near
    if self.orthographic then
        -- Parallel projection has no eye point, so geometry behind the camera plane is
        -- legitimately visible; clipping it at a positive near would cut off tilted views.
        n = self.orthoNear or -far
        assert(far > n, 'Orthographic Camera3D requires orthoNear < far')
    else
        assert(n > 0 and far > n, 'Camera3D requires 0 < near < far')
    end
    self.nearClip, self.farClip = n, far
    local q = self.projection
    for j = 1, 16 do
        q[j] = 0
    end
    if self.orthographic then
        q[1] = 2 * self.pixelsPerUnit / width
        q[6] = -2 * self.pixelsPerUnit / height
        q[11] = 2 / (far - n)
        q[12] = -(far + n) / (far - n)
        q[16] = 1
    else
        q[1] = 2 * self.focal / width
        q[6] = -2 * self.focal / height
        q[11] = (far + n) / (far - n)
        q[12] = -2 * far * n / (far - n)
        q[15] = 1
    end
    M.multiply(q, v, self.viewProjection)
    state = state or {}
    self._cameraProjectionState = state
    state[1], state[2], state[3] = self._renderRevision, width, height
    state[4], state[5], state[6], state[7] =
        self.focalLength, self.referenceHeight, self.near, self.far
    state[8], state[9], state[10] = self.projectionMode, self.orthoSize, self.orthoNear
end

function Camera3D:project(p)
    local x, y, z = M.transform(self.view, p[1], p[2], p[3])
    if z < self.nearClip or z > self.far then
        return
    end
    if self.orthographic then
        local scale = self.pixelsPerUnit
        return self.width / 2 + x * scale, self.height / 2 - y * scale, z
    end
    return self.width / 2 + x * self.focal / z, self.height / 2 - y * self.focal / z, z
end

-- Screen position of a view-space point; the caller handles near-plane clipping.
function Camera3D:viewToScreen(x, y, z)
    if self.orthographic then
        local scale = self.pixelsPerUnit
        return self.width / 2 + x * scale, self.height / 2 - y * scale
    end
    return self.width / 2 + x * self.focal / z, self.height / 2 - y * self.focal / z
end

-- Screen pixels covered by one world unit at view depth z.
function Camera3D:pixelsPerUnitAt(depth)
    if self.orthographic then
        return self.pixelsPerUnit
    end
    return self.focal / depth
end

-- World-space ray through a screen pixel. Perspective rays start at the eye; orthographic
-- rays start on the near-parallel plane through the eye and share the forward direction.
-- Fills and returns the optional out tables to keep picking allocation-free.
function Camera3D:screenRay(x, y, origin, direction)
    origin, direction = origin or {}, direction or {}
    local r, u, f = self.right, self.up, self.forward
    local p = self.worldPosition or self.position
    if self.orthographic then
        local dx = (x - self.width * 0.5) / self.pixelsPerUnit
        local dy = -(y - self.height * 0.5) / self.pixelsPerUnit
        for i = 1, 3 do
            origin[i] = p[i] + r[i] * dx + u[i] * dy
            direction[i] = f[i]
        end
        return origin, direction
    end
    local dx = (x - self.width * 0.5) / self.focal
    local dy = -(y - self.height * 0.5) / self.focal
    for i = 1, 3 do
        origin[i] = p[i]
        direction[i] = r[i] * dx + u[i] * dy + f[i]
    end
    return origin, direction
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
