local Game = require('source.runtime.game')

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
    scene.root:find('World3D/World2D'):scrollBy(scene.demo.right, 310)
    self.manager:draw()
    katsa.graphics.captureScreenshot(function(image)
        local path = assert(os.getenv('KATSA_PREVIEW_PATH'), 'Set KATSA_PREVIEW_PATH')
        local file = assert(io.open(path, 'wb'))
        file:write(image:encode('png'):getString())
        file:close()
        image:release()
        print('V105 PREVIEW COMPLETE')
        katsa.event.quit()
    end)
end

return Preview
