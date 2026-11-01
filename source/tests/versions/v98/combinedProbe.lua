-- Same-state paired rendering diagnostic; not an end-to-end gameplay FPS claim.
local T = {}
T.__index = T

function T.new(manager)
    io.stdout:setvbuf('no')
    jit.off()
    jit.flush()
    katsa.errorhandler = function(m)
        print('FAILED Combined probe ' .. tostring(m))
        os.exit(1)
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
    local scene = assert(self.manager:switch(require('source.game.runtime.game').new, 'combined'))
    local env = scene.world.environment
    env.shadows.enabled = false
    env.debug.gizmos.enabled = false
    local modes =
        { { 'Direct', true }, { 'Direct', false }, { 'Masked', true }, { 'Masked', false } }
    local samples = { {}, {}, {}, {} }
    local x, yaw = scene.camera.position[1], scene.camera.rotation[2]
    for frame = 1, 75 do
        scene.camera.position[1] = x + math.sin(frame / 30) * 30
        scene.camera.rotation[2] = yaw + math.sin(frame / 30) * 10
        self.manager:update(1 / 60)
        local reference
        for step = 1, 4 do
            local index = (step + frame - 2) % 4 + 1
            local mode = modes[index]
            env.render.lightLoop = mode[1]
            env.render.depthPrepass = mode[2]
            scene.renderer:invalidate()
            local started = katsa.timer.getTime()
            self.manager:draw()
            katsa.graphics.flushBatch()
            local image = scene.renderer.canvas:newImageData()
            katsa.graphics.present()
            local elapsed = (katsa.timer.getTime() - started) * 1000
            if frame > 20 then
                samples[index][#samples[index] + 1] = elapsed
            end
            if frame % 15 == 0 then
                local hash = katsa.data.hash('sha256', image:getString())
                reference = reference or hash
                assert(
                    hash == reference,
                    'Lighting/depth mode pixels differ at frame ' .. frame .. ' mode ' .. index
                )
            end
            image:release()
        end
    end
    for i, mode in ipairs(modes) do
        table.sort(samples[i])
        local sum = 0
        for _, v in ipairs(samples[i]) do
            sum = sum + v
        end
        print(
            'COMBINED',
            mode[1],
            mode[2],
            'mean/p50/p95',
            sum / #samples[i],
            samples[i][math.ceil(#samples[i] * 0.5)],
            samples[i][math.ceil(#samples[i] * 0.95)]
        )
    end
    print('PAIRED COMBINED COMPLETE')
    katsa.event.quit()
end

return T
