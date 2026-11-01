local Game = require('source.game.runtime.game')
local Preview = {}
Preview.__index = Preview

function Preview.new(manager)
    io.stdout:setvbuf('no')
    return setmetatable({
        manager = manager,
        stage = 0,
        prefix = assert(os.getenv('KATSA_UI_PREVIEW_PREFIX'), 'Set an absolute preview prefix'),
    }, Preview)
end

function Preview:update()
    if self.stage == 1 then
        local scene = assert(self.manager:switch(Game.new, 'original'))
        scene.workspace:toggle(true)
        scene.workspace.progress = 1
        scene.workspace:positionPanel()
        scene.workspace:select(scene.world.byName.SpinningCube)
        self.stage = 2
    end
end

function Preview:draw()
    if self.stage ~= 0 and self.stage ~= 2 then
        return
    end
    local menu = self.stage == 0
    self.stage = menu and -1 or 3
    love.graphics.captureScreenshot(function(image)
        local path = self.prefix .. (menu and '-menu.png' or '-workspace.png')
        local file = assert(io.open(path, 'wb'))
        file:write(image:encode('png'):getString())
        file:close()
        image:release()
        print('PREVIEW', path)
        if menu then
            self.stage = 1
        else
            love.event.quit()
        end
    end)
end

return Preview
