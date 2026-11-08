-- Typing into the menu search box filters the scene list (text input reaches the focused box).
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
    local host = require('source.game.runtime.application').new(self.manager, 'menu')
    host:load()
    local function rows()
        return #host.ui:find('LevelList', true).children
    end
    local all = rows()
    self:check(all > 5, 'the menu lists scenes')
    host.searchBox:focus()
    for _, char in ipairs({ 'c', 'a', 'r', 's' }) do
        host:textinput(char)
    end
    self:check(host.searchBox.text == 'cars', 'typed characters reach the search box')
    self:check(rows() >= 1 and rows() < all, 'the list is filtered by the typed words')
    host:keypressed('backspace')
    self:check(host.searchBox.text == 'car', 'Backspace edits the search box')
    host:keypressed('return')
    self:check(host.searchBox.text == 'car' and not host.pending, 'Enter in the search box does not start a scene')
    print('PASSED ' .. self.count .. ' v108.7 menuSearch checks')
    katsa.event.quit()
end

return Tests
