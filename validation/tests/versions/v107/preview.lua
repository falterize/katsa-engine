local Application = require('source.game.runtime.application')

local Preview = {}
Preview.__index = Preview

function Preview.new(manager)
    local name = os.getenv('KATSA_PREVIEW_SCENE') or 'physicsMixed'
    local scene = assert(manager:switch(Application.new, name))
    if os.getenv('KATSA_PREVIEW_WORKSPACE') == '1' and scene.workspace then
        scene.workspace:toggle(true)
        scene.workspace.selected = scene.ui
        name = name .. '-workspace'
    end
    return setmetatable({ scene = scene, name = name, frames = 0 }, Preview)
end

function Preview:update()
    self.frames = self.frames + 1
end

function Preview:draw()
    if self.frames < 90 or self.captured then
        return
    end
    self.captured = true
    katsa.graphics.captureScreenshot(function(data)
        local path = 'validation-v107/' .. self.name .. '.png'
        assert(katsa.filesystem.createDirectory('validation-v107'))
        data:encode('png', path)
        print('PASSED PREVIEW', katsa.filesystem.getSaveDirectory() .. '/' .. path)
        katsa.event.quit()
    end)
end

return Preview
