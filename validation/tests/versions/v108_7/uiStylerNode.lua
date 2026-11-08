-- The uiStyler plugin shows up as a UIStyler node whose theme and styles folder drive the sheet.
local Previous = require('validation.tests.versions.v107.physics2D')
local Tests = setmetatable({}, { __index = Previous })
Tests.__index = Tests

function Tests.new(manager)
    return setmetatable(Previous.new(manager), Tests)
end

function Tests:update() end

function Tests:draw()
    if self.done then
        return
    end
    self.done = true
    self.host = require('source.game.runtime.application').new(self.manager, 'launcherShowcase')
    self.host:load()
    local node
    for _, candidate in ipairs(self.host.world.root:getDescendants()) do
        if candidate.className == 'UIStyler' then
            node = candidate
        end
    end
    self:check(node ~= nil, 'launcherShowcase has a UIStyler node in its tree')
    local styler = node:getStyler()
    self:check(styler:getTheme() == 'dark' and node.theme == 'dark', 'The node applies its theme')
    local first = self.host.ui:find('Launcher', true)
    local before = first and first.backgroundColor
    node.theme = 'light'
    node:update()
    self:check(styler:getTheme() == 'light', 'Editing the theme property switches the theme')
    node:setTheme('dark')
    self:check(styler:getTheme() == 'dark' and node.theme == 'dark', 'setTheme keeps the property in step')
    local options = require('source.engine.plugins').require('uiStyler').themeNames()
    self:check(#options == 2, 'The theme property offers the defined themes')
    print('PASSED ' .. self.count .. ' v108.7 UIStyler node checks')
    katsa.event.quit()
end

return Tests
