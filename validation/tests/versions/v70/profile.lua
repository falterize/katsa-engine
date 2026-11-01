local T = {}
T.__index = T

function T.new(manager)
    katsa.window.setMode(960, 540, { vsync = 0, depth = 24, stencil = 8 })
    local scene = assert(manager:switch(require('source.game.runtime.game').new, 'combined'))
    scene.world.environment.render.lightLoop = 'Masked'
    scene.world.environment.render.frameCache = false
    scene.world.environment.shadows.enabled = false
    scene.world.environment.gizmos.enabled = false
    return setmetatable({ scene = scene, frame = 0 }, T)
end

function T:update() end

function T:draw()
    self.frame = self.frame + 1
    if self.frame == 6 then
        local s = self.scene
        local masks = require('source.engine.graphics.pipeline.lightMasks')
        print('BATCH GROUPS', #s.renderer.batches.groups)
        local fullImage
        for _, all in ipairs({ true, false }) do
            masks.forceAll = all
            for i = 1, 3 do
                s.renderer:draw(s.world, s.camera, s.time)
                local p = s.renderer.canvas:newImageData()
                p:release()
            end
            local t = katsa.timer.getTime()
            for i = 1, 10 do
                s.renderer:draw(s.world, s.camera, s.time)
                local p = s.renderer.canvas:newImageData()
                p:release()
            end
            print(
                'PROFILE '
                    .. (all and 'Full' or 'Filtered')
                    .. string.format(' %.3f ms synchronized draw', (katsa.timer.getTime() - t) * 100)
            )
            local image = s.renderer.canvas:newImageData()
            if all then
                fullImage = image
            else
                local error = 0
                for y = 0, image:getHeight() - 1, 7 do
                    for x = 0, image:getWidth() - 1, 7 do
                        local a, b, c = fullImage:getPixel(x, y)
                        local d, e, f = image:getPixel(x, y)
                        error = math.max(error, math.abs(a - d), math.abs(b - e), math.abs(c - f))
                    end
                end
                assert(error < 0.005, 'Light filtering changed rendered lighting')
                print('MAX FILTER PIXEL DIFFERENCE', error)
                image:release()
                fullImage:release()
            end
        end
        for k, v in pairs(s.renderer.stats) do
            if type(v) == 'number' then
                print(k, v)
            end
        end
        katsa.event.quit()
    end
end

return T
