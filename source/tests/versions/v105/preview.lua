local Game = require('source.game.runtime.game')

local Preview = {}
Preview.__index = Preview

function Preview.new(manager)
    return setmetatable({ manager = manager }, Preview)
end

function Preview:update() end

function Preview:draw()
    if self.done then
        return
    end
    self.done = true
    local scene = assert(self.manager:switch(Game.new, 'uiGallery'))
    self.manager:update(1 / 60)
    scene.ui:scrollBy(scene.demo.right, 310)
    self.manager:draw()
    love.graphics.captureScreenshot(function(image)
        local path = assert(os.getenv('KATSA_PREVIEW_PATH'), 'Set KATSA_PREVIEW_PATH')
        local file = assert(io.open(path, 'wb'))
        file:write(image:encode('png'):getString())
        file:close()
        image:release()
        print('V105 PREVIEW COMPLETE')
        love.event.quit()
    end)
end

return Preview
