local Orbit = {}
Orbit.__index = Orbit

function Orbit.new(scene, player)
    local settings, camera = scene.settings.camera, scene.camera
    camera.near, camera.far, camera.drawDistance = 0.05, 4000, 4000
    camera.focalLength = camera.referenceHeight / (2 * math.tan(math.rad(settings.fov) / 2))
    return setmetatable({
        scene = scene,
        player = player,
        settings = settings,
        distance = 0,
        yaw = 0,
        pitch = 0,
        start = {},
        finish = {},
        hit = {},
    }, Orbit)
end

function Orbit:look(x, y)
    self.yaw = (self.yaw + x * self.settings.sensitivity) % 360
    self.pitch = math.max(-90, math.min(90, self.pitch - y * self.settings.sensitivity))
    self.player.cameraYaw = math.rad(self.yaw)
end

function Orbit:zoom(amount)
    self.distance = math.max(
        self.settings.minDistance,
        math.min(self.settings.maxDistance, self.distance - amount * self.settings.zoomSpeed)
    )
end

function Orbit:update()
    if self.scene.freeDebugCamera then
        return
    end
    local player, camera = self.player, self.scene.camera
    local matrix = player.body.node:getRenderWorldMatrix()
    local pivotY = matrix[8] + (player.height - player.settings.standingHeight) / 2 + 0.5
    local pitch, yaw = math.rad(self.pitch), math.rad(self.yaw)
    local x, y, z =
        math.sin(yaw) * math.cos(pitch), math.sin(pitch), math.cos(yaw) * math.cos(pitch)
    local offset = 0.5 - self.distance
    local start, finish = self.start, self.finish
    start[1], start[2], start[3] = matrix[4], pivotY, matrix[12]
    finish[1], finish[2], finish[3] =
        start[1] + x * offset, pivotY + y * offset, start[3] + z * offset
    if self.distance > 0.5 then
        local hit = self.scene.physics:raycast(start, finish, player.rayFilter, self.hit)
        if hit then
            for i = 1, 3 do
                finish[i] = hit.position[i] + hit.normal[i] * 0.05
            end
        end
    end
    for i = 1, 3 do
        camera.position[i] = finish[i]
    end
    -- A tiny pitch clamp keeps a valid camera basis at the source's +/-90 limits.
    camera.rotation[1], camera.rotation[2] = math.max(-89.99, math.min(89.99, self.pitch)), self.yaw
end

return Orbit
