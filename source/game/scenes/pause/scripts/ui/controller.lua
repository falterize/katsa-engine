local Input = require('source.engine.input.input')

local Pause = {}
Pause.__index = Pause

function Pause.new(manager)
    return setmetatable({ manager = manager, simulation = false }, Pause)
end

function Pause:load()
    self.settings = self.package.settings
    self.resources = self.manager.resources:scope(nil, self.package.paths)
    require('source.engine.ui.sceneRoot').create(self, 1280, 720)
    self.ui.content.name = 'Pause'
    self.input = Input.new(self)
    self.ui:container(
        { size = { 1, 0, 1, 0 }, backgroundColor = { 0, 0, 0 }, backgroundTransparency = 0.4 },
        self.ui.content
    )
    self.panel = self.ui:container({
        position = { 0.5, 0, 0.5, 0 },
        size = { 1, -32, 0, 240 },
        anchorPoint = { 0.5, 0.5 },
        backgroundColor = { 0.035, 0.065, 0.105 },
    }, self.ui.content)
    self.ui:text({
        position = { 0, 16, 0, 12 },
        size = { 1, -32, 0, 40 },
        text = 'Paused',
        fontSize = 26,
        align = 'left',
    }, self.panel)
    local list = self.ui:scroll(
        { position = { 0, 12, 0, 62 }, size = { 1, -24, 1, -74 }, length = 112 },
        self.panel
    )
    self.ui:button({
        size = { 1, 0, 0, 48 },
        text = 'Resume',
        fontSize = 19,
        backgroundColor = { 0.1, 0.32, 0.45 },
        onPress = function()
            self.manager:pop()
        end,
    }, list)
    self.ui:button({
        position = { 0, 0, 0, 60 },
        size = { 1, 0, 0, 48 },
        text = 'Return to menu',
        fontSize = 19,
        backgroundColor = { 0.085, 0.135, 0.19 },
        onPress = function()
            self.manager:switch(require('source.game.runtime.menu').new)
        end,
    }, list)
    self:resize(katsa.graphics.getDimensions())
end

function Pause:draw()
    self.ui:draw()
    katsa.graphics.setColor(1, 1, 1, 1)
end

function Pause:resize(w, h)
    self.ui:fit(w, h)
    self.panel.size =
        { 0, math.min(420, self.ui.width - 32), 0, math.min(240, self.ui.height - 24) }
end

function Pause:pointerpressed(id, x, y)
    self.input:press(id, x, y)
end

function Pause:pointermoved(id, x, y, dx, dy)
    self.input:move(id, x, y, dx, dy)
end

function Pause:pointerreleased(id)
    self.input:release(id)
end

function Pause:keypressed(key)
    if key == 'escape' then
        self.manager:pop()
    end
end

function Pause:exit()
    self.input:reset()
end

function Pause:release()
    self.world:release()
    self.resources:release()
end

return Pause
