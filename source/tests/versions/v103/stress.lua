local T = {}
T.__index = T

function T.new(manager)
    io.stdout:setvbuf('no')
    if os.getenv('KATSA_TEST_INTERPRETER') == '1' then
        jit.off()
        jit.flush()
    end
    katsa.window.setMode(810, 456, { vsync = 0, depth = 24, stencil = 8 })
    return setmetatable({ manager = manager }, T)
end

function T:update() end

function T:draw()
    if self.done then
        return
    end
    self.done = true
    local zones = {
        'animationPhysicsLab',
        'platformer',
        'collisionBox',
        'collisionModels',
        'shadows',
        'nightPlayer',
        'flyingAudio',
        'graphicsLab',
    }
    for _, zone in ipairs(zones) do
        katsa.math.setRandomSeed(384)
        math.randomseed(384)
        local scene = assert(self.manager:switch(require('source.game.runtime.game').new, zone))
        assert(
            not scene.physics or scene.physics.backendName == 'jolt',
            'Stress must use real Jolt'
        )
        local frames = zone == 'animationPhysicsLab' and 2400
            or zone == 'graphicsLab' and 120
            or 360
        for frame = 1, frames do
            self.manager:update(1 / 60)
            for _, body in ipairs(scene.physics and scene.physics.bodies or {}) do
                for i = 1, 3 do
                    local v = body.object.position[i]
                    assert(v == v and math.abs(v) < 100000, 'Divergent body: ' .. body.object.name)
                end
            end
            if frame % 60 == 0 then
                katsa.event.pump()
                self.manager:draw()
                katsa.graphics.present()
                local data = scene.renderer.canvas:newImageData()
                data:release()
            end
        end
        if scene.physics then
            scene.physics.debugEnabled = true
            self.manager:draw()
            katsa.graphics.present()
            scene.physics.debugEnabled = false
        end
        print(
            'PASS JOLT STRESS',
            zone,
            frames,
            'frames',
            scene.physics and #scene.physics.bodies or 0,
            'bodies'
        )
    end
    self.manager:switch(require('source.game.runtime.menu').new)
    collectgarbage('collect')
    assert(#self.manager.journal.entries == 0, 'Runtime journal errors')
    print('JOLT STRESS COMPLETE')
    katsa.event.quit()
end

return T
