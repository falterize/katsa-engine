local T = {}
T.__index = T

function T.new(manager)
    io.stdout:setvbuf('no')
    love.window.setMode(1280, 720, { vsync = 0, highdpi = true, depth = 24, stencil = 8 })
    print('PREVIEW DPI', love.graphics.getDPIScale())
    return setmetatable({ manager = manager, index = 0, frame = 0 }, T)
end

function T:update()
    self.frame = self.frame + 1
    if self.frame == 1 then
        self.index = self.index + 1
        self.zone = ({ 'menu', 'animationPhysicsLab', 'platformer', 'surfaceGallery' })[self.index]
        if not self.zone then
            love.event.quit()
            return
        end
        love.math.setRandomSeed(384)
        math.randomseed(384)
        if self.zone == 'menu' then
            self.manager:switch(require('source.game.runtime.menu').new)
        else
            local scene =
                assert(self.manager:switch(require('source.game.runtime.game').new, self.zone))
            scene.showStats = false
        end
    end
end

function T:draw()
    if self.frame ~= 20 then
        return
    end
    local name = self.zone
    love.graphics.captureScreenshot(function(data)
        local path = (os.getenv('KATSA_CAPTURE_PREFIX') or '') .. name .. '.png'
        local encoded = data:encode('png')
        local f = assert(io.open(path, 'wb'))
        f:write(encoded:getString())
        f:close()
        encoded:release()
        data:release()
        print('CAPTURE', path)
        self.frame = 0
    end)
end

return T
