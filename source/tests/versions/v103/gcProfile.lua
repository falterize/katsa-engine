local T = {}
T.__index = T

function T.new(manager)
    io.stdout:setvbuf('no')
    if os.getenv('KATSA_TEST_INTERPRETER') == '1' then
        jit.off()
        jit.flush()
    end
    love.window.setMode(810, 456, { vsync = 0, depth = 24, stencil = 8 })
    return setmetatable({ manager = manager }, T)
end

function T:update() end

function T:draw()
    if self.done then
        return
    end
    self.done = true
    print('JIT', jit.status())
    print('case,backend,round,KB allocated per update with GC stopped,update mean ms')
    for _, zone in ipairs({ 'animationPhysicsLab', 'animationLab', 'combined' }) do
        for round = 1, 3 do
            love.math.setRandomSeed(384)
            math.randomseed(384)
            local scene = assert(self.manager:switch(require('source.game.runtime.game').new, zone))
            scene.showStats = false
            for i = 1, 90 do
                self.manager:update(1 / 60)
            end
            collectgarbage('collect')
            collectgarbage('stop')
            local memory, start = collectgarbage('count'), love.timer.getTime()
            for i = 1, 120 do
                self.manager:update(1 / 60)
            end
            local elapsed = (love.timer.getTime() - start) * 1000 / 120
            local allocated = (collectgarbage('count') - memory) / 120
            collectgarbage('restart')
            collectgarbage('collect')
            print(
                string.format(
                    '%s,%s,%d,%.3f,%.3f',
                    zone,
                    scene.physics and (scene.physics.backendName or 'oimo') or '-',
                    round,
                    allocated,
                    elapsed
                )
            )
            love.event.pump()
        end
    end
    assert(#self.manager.journal.entries == 0, 'Runtime journal errors')
    print('GC PROFILE COMPLETE')
    love.event.quit()
end

return T
