local ipairs = require('source.engine.math.array').ipairs
local Input = require('source.engine.input.input')
local Samples = require('../catalog.samples')

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
    self.entries = Samples.entries()
    self.tab, self.query = 'All', ''
    self.search = self.ui:create('TextBox', {
        name = 'CatalogSearch',
        position = { 0, 16, 0, 110 },
        size = { 1, -32, 0, 34 },
        text = '',
        placeholderText = 'Search nodes or plugins',
        fontSize = 16,
        backgroundColor = { 0.08, 0.16, 0.24 },
        backgroundTransparency = 0,
        onTextChanged = function(_, text)
            self.query = text:lower()
            self:refill()
        end,
    }, self.panel)
    self.tabButtons = {}
    local tabs = Samples.TABS
    for i, name in ipairs(tabs) do
        self.tabButtons[name] = self.ui:button({
            position = { (i - 1) / #tabs, (i == 1) and 16 or 2, 0, 152 },
            size = { 1 / #tabs, (i == 1 or i == #tabs) and -18 or -4, 0, 32 },
            text = name,
            fontSize = 13,
            onPress = function()
                self.tab = name
                self:refill()
            end,
        }, self.panel)
    end
    self.count = self.ui:text({
        position = { 0, 16, 0, 190 },
        size = { 1, -32, 0, 22 },
        text = '',
        textScaled = true,
        maxTextSize = 14,
    }, self.panel)
    self.list = self.ui:scroll(
        { position = { 0, 16, 0, 216 }, size = { 1, -32, 1, -232 }, length = 0 },
        self.panel
    )
    self:refill()
    self:resize(katsa.graphics.getDimensions())
end

-- Rebuilds the list for the current tab and search text.
function Scene:refill()
    for _, child in ipairs(self.list:getChildren()) do
        child:destroy()
    end
    local shown = 0
    for _, entry in ipairs(self.entries) do
        local plugin = entry.plugin or ''
        local haystack = (entry.name .. ' ' .. plugin .. ' ' .. entry.tab):lower()
        if (self.tab == 'All' or entry.tab == self.tab) and haystack:find(self.query, 1, true) then
            shown = shown + 1
            local label = entry.name .. ' / ' .. (entry.plugin and ('plugin ' .. entry.plugin .. ' / ') or '') .. entry.zone
            self.ui:button({
                position = { 0, 0, 0, (shown - 1) * 46 },
                size = { 1, 0, 0, 42 },
                text = label,
                fontSize = 16,
                align = 'left',
                onPress = function()
                    self.manager:switch(require('source.game.runtime.game').new, entry.zone, entry.name)
                end,
            }, self.list)
        end
    end
    self.list.length = shown * 46
    self.count.text = shown .. ' nodes'
    for name, button in pairs(self.tabButtons) do
        button.backgroundColor = name == self.tab and { 0.12, 0.32, 0.5 } or { 0.08, 0.16, 0.25 }
    end
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
