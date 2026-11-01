-- Paired full-manager draw check for lazy field dispatch after programs are warm.
local T = {}
T.__index = T

function T.new(manager)
    io.stdout:setvbuf('no')
    jit.off()
    jit.flush()
    love.errorhandler = function(m)
        print('FAILED dispatch probe ' .. tostring(m))
        os.exit(1)
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
    local Renderer = require('source.engine.graphics.pipeline.renderer')
    local Shadows = require('source.engine.graphics.shadows.shadows')
    local rIndex, sIndex = Renderer.__index, Shadows.__index
    for _, zone in ipairs({ 'combined', 'animationPhysicsLab' }) do
        local scene = assert(self.manager:switch(require('source.game.runtime.game').new, zone))
        local renderer = scene.renderer
        if zone == 'combined' then
            scene.world.environment.shadows.enabled = false
        end
        local general, wire, shadow = renderer.shader, renderer.wireShader, renderer.shadows.shader
        local totals, checks, draws = { 0, 0 }, { 0, 0 }, { 0, 0 }
        for frame = 1, 50 do
            scene.camera.rotation[2] = math.sin(frame / 30) * 5
            self.manager:update(1 / 60)
            for step = 1, 2 do
                local mode = (frame + step) % 2 + 1
                Renderer.__index = mode == 1 and Renderer or rIndex
                Shadows.__index = mode == 1 and Shadows or sIndex
                renderer:invalidate()
                local t = love.timer.getTime()
                self.manager:draw()
                love.graphics.flushBatch()
                local drawn = love.timer.getTime()
                local image = renderer.canvas:newImageData()
                image:release()
                love.graphics.present()
                if frame > 10 then
                    totals[mode] = totals[mode] + (love.timer.getTime() - t) * 1000
                    draws[mode] = draws[mode] + (drawn - t) * 1000
                    checks[mode] = checks[mode] + renderer.stats.cacheCheckMilliseconds
                end
            end
        end
        Renderer.__index, Shadows.__index = rIndex, sIndex
        print(
            'PAIRED',
            zone,
            'table/lazy mean total',
            totals[1] / 40,
            totals[2] / 40,
            'draw',
            draws[1] / 40,
            draws[2] / 40,
            'checks',
            checks[1] / 40,
            checks[2] / 40
        )
    end
    print('PAIRED DISPATCH COMPLETE')
    love.event.quit()
end

return T
