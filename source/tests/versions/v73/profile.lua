local T = {}
T.__index = T

function T.new(manager)
    katsa.window.setMode(960, 540, { vsync = 0, depth = 24, stencil = 8 })
    local scene = assert(manager:switch(require('source.game.runtime.game').new, 'combined'))
    scene.world.environment.shadows.enabled = false
    scene.world.environment.gizmos.enabled = false
    return setmetatable({ scene = scene }, T)
end

function T:update() end

function T:draw()
    local scene = self.scene
    if self.done then
        return
    end
    self.done = true
    local r, w, c = scene.renderer, scene.world, scene.camera
    for i = 1, 30 do
        r:draw(w, c, i / 60, true)
    end
    for _, enabled in ipairs({ false, true }) do
        w.environment.render.frameCache = enabled
        for i = 1, 10 do
            r:draw(w, c, 2 + i / 60, true)
        end
        local start = katsa.timer.getTime()
        local reused = 0
        for i = 1, 30 do
            r:draw(w, c, 3 + i / 60, true)
            reused = reused + (r.stats.frameReused and 1 or 0)
            local image = r.canvas:newImageData()
            image:release()
        end
        print(
            'CACHE',
            enabled,
            (katsa.timer.getTime() - start) * 1000 / 30,
            'ms synchronized frame',
            'REUSED',
            reused
        )
    end
    local start = katsa.timer.getTime()
    for i = 1, 120 do
        r:draw(w, c, 4 + i / 60, true)
    end
    print('IDLE CPU', (katsa.timer.getTime() - start) * 1000 / 120, 'ms/frame')
    local start = katsa.timer.getTime()
    for i = 1, 30 do
        c.rotation[2] = c.rotation[2] + 0.1
        r:draw(w, c, 6 + i / 60, true)
        local image = r.canvas:newImageData()
        image:release()
    end
    print('MOVING CAMERA', (katsa.timer.getTime() - start) * 1000 / 30, 'ms synchronized frame')
    katsa.event.quit()
end

return T
