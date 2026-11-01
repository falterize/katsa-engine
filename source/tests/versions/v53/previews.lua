local Preview = {}
Preview.__index = Preview
local stages = { { 1280, 720 }, { 360, 640 } }

function Preview.new(manager)
    return setmetatable({ manager = manager, index = 0, frame = 0 }, Preview)
end

function Preview:update()
    self.frame = self.frame + 1
    if self.frame % 6 == 1 then
        self.index = self.index + 1
        local stage = stages[self.index]
        if not stage then
            print('v53 previews complete')
            katsa.event.quit()
            return
        end
        katsa.window.setMode(stage[1], stage[2], { depth = 24, stencil = 8, vsync = 0 })
        self.scene = self.manager:switch(require('source.game.runtime.game').new, 'physics')
        self.scene.showStats = true
    elseif self.frame % 6 == 5 then
        self.capture = true
    end
end

function Preview:draw()
    if self.capture then
        self.capture = nil
        local stage = stages[self.index]
        katsa.graphics.captureScreenshot(function(image)
            image:encode('png', 'v53-physics-' .. stage[1] .. 'x' .. stage[2] .. '.png')
            image:release()
        end)
    end
end

return Preview
