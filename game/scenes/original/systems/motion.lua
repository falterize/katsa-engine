local Motion = {}
Motion.__index = Motion

function Motion.create(state, scene)
    return setmetatable({ scene = scene }, Motion)
end

function Motion:update3D(dt)
    local scene = self.scene
    if scene.demoAnimations then
        local o = scene.world.byName
        local angle = scene.time * 200
        local cube = o.SpinningCube
        cube.position[2] = math.sin(math.rad(angle)) * 15
        cube.rotation[1], cube.rotation[2], cube.rotation[3] = angle, angle, angle
        local v = math.min(math.sin(math.rad(scene.time * 250)), 0)
        o.LeftCube.position[1] = v * 30
        o.RightCube.position[1] = 10 - v * 30
        for _, name in ipairs({ 'LeftCube', 'RightCube' }) do
            local s = o[name].size
            s[1], s[2], s[3] = (0.5 - v * 0.5) * 20, (2 + v) * 20, (2 + v) * 20
        end
    end
    local motion = scene.rainbowMotion
    if motion.enabled and scene.time >= (scene.nextRainbow or 0) then
        scene.nextRainbow = scene.time + 1 / motion.hz
        local angle =
            math.rad(math.sin(scene.time * 2 * math.pi / math.max(0.1, motion.period)) * motion.arc)
        local l = scene.world.lights[2]
        l.position[1] = motion.center[1] + math.sin(angle) * motion.amplitude
        l.position[2] = motion.center[2]
        l.position[3] = motion.center[3] + (math.cos(angle) - 1) * motion.amplitude
    end
    if scene.billboardMotion then
        scene.billboardPhase = (scene.billboardPhase or 0) + dt * 40
        local z = 160 + 60 * math.sin(math.rad(scene.billboardPhase))
        scene.boards.fixed.position[3] = z
        scene.boards.moving.position[3] = z
    end
end

return Motion
