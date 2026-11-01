-- Controlled 960x540 stress measurement; does not alter production scene defaults.
local T = {}
T.__index = T

function T.new(manager)
    love.window.setMode(960, 540, { vsync = 0, depth = 24, stencil = 8 })
    local scene = assert(manager:switch(require('source.game.runtime.game').new, 'combined'))
    scene.world.environment.render.frameCache = false
    scene.world.environment.shadows.enabled = false
    scene.world.environment.gizmos.enabled = false
    return setmetatable({ scene = scene }, T)
end

function T:update() end

function T:draw()
    if self.done then
        return
    end
    self.done = true
    local scene = self.scene

    local function measure(label, count, callback)
        for i = 1, 5 do
            callback()
        end
        collectgarbage('collect')
        local start = love.timer.getTime()
        for i = 1, count do
            callback()
        end
        print(label, string.format('%.3f ms', (love.timer.getTime() - start) * 1000 / count))
    end
    measure('UPDATE', 120, function()
        scene:update(1 / 60, 1 / 60)
    end)
    measure('PREPARE', 120, function()
        scene.renderer:prepare(scene.world, scene.camera, scene.time)
    end)
    measure('DRAW_SYNC', 20, function()
        scene.renderer:draw(scene.world, scene.camera, scene.time)
        local image = scene.renderer.canvas:newImageData()
        image:release()
    end)
    print(
        'OBJECTS',
        #scene.world.objects,
        'VISIBLE',
        scene.renderer.stats.objects,
        'LIGHTS',
        scene.renderer.lights.count,
        'BATCHES',
        #scene.renderer.batches.groups,
        'SIZE',
        scene.renderer.canvas:getPixelDimensions()
    )
    love.event.quit()
end

return T
