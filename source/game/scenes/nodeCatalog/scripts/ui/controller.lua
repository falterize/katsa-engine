local ipairs = require('source.engine.math.array').ipairs
local Input = require('source.engine.input.input')
local Samples = require('scene.scripts.catalog.samples')

local Scene = {}
Scene.__index = Scene

function Scene.new(manager)
    return setmetatable({ manager = manager, simulation = false }, Scene)
end

function Scene:load()
    self.settings = self.package.settings
    self.resources =
        self.manager.resources:scope(require('source.game.data.manifest'), self.package.paths)
    require('source.engine.ui.sceneRoot').create(self, 1280, 720)
    self.input = Input.new(self)
    self.panel = self.ui:container({
        position = { 0.5, 0, 0.5, 0 },
        size = { 1, -24, 1, -24 },
        anchorPoint = { 0.5, 0.5 },
        backgroundColor = { 0.035, 0.065, 0.105 },
    }, self.ui.content)
    self.ui:text({
        position = { 0, 16, 0, 12 },
        size = { 1, -32, 0, 44 },
        text = 'Node catalog / runnable samples',
        textScaled = true,
        maxTextSize = 26,
    }, self.panel)
    self.ui:button({
        position = { 0, 16, 0, 64 },
        size = { 1, -32, 0, 38 },
        text = 'Back to scenes',
        onPress = function()
            self.manager:switch(require('source.game.runtime.menu').new)
        end,
    }, self.panel)
    self.list = self.ui:scroll(
        { position = { 0, 16, 0, 112 }, size = { 1, -32, 1, -128 }, length = 0 },
        self.panel
    )
    for i, name in ipairs(Samples.names()) do
        local kind = name
        self.ui:button({
            position = { 0, 0, 0, (i - 1) * 46 },
            size = { 1, 0, 0, 42 },
            text = kind .. ' / ' .. Samples.zone(kind),
            fontSize = 16,
            align = 'left',
            onPress = function()
                self.manager:switch(
                    require('source.game.runtime.game').new,
                    Samples.zone(kind),
                    kind
                )
            end,
        }, self.list)
        self.list.length = i * 46
    end
    self:resize(katsa.graphics.getDimensions())
end

function Scene:resize(w, h)
    self.ui:fit(w, h)
    self.panel.size = { 0, math.min(760, self.ui.width - 24), 1, -24 }
end

function Scene:update(dt, realDt)
    self.input:update(dt)
end

function Scene:draw()
    katsa.graphics.clear(0.025, 0.04, 0.065, 1)
    self.ui:draw()
end

function Scene:pointerpressed(id, x, y)
    self.input:press(id, x, y)
end

function Scene:pointermoved(id, x, y, dx, dy)
    self.input:move(id, x, y, dx, dy)
end

function Scene:pointerreleased(id, x, y)
    self.input:release(id, x, y)
end

function Scene:wheelmoved(x, y)
    self.ui:wheel(katsa.mouse.getX(), katsa.mouse.getY(), y, x)
end

function Scene:exit()
    self.input:reset()
end

function Scene:release()
    self.world:release()
    self.resources:release()
end

return Scene
