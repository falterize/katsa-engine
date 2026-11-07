-- Extra OS windows on the shared graphics context, and window opacity.
local Module = {}

function Module.run(self)
    local window = katsa.window.create(200, 120, { title = 'Second', x = 50, y = 60, hidden = false })
    self:check(window ~= nil and window:isOpen(), 'A second window opens on the shared context')
    window:setPosition(80, 90)
    window:setSize(220, 140)
    local width, height = window:getSize()
    self:check(width == 220 and height == 140, 'The second window reports its size')
    local drawn = false
    window:draw(function()
        katsa.graphics.clear(0.2, 0.4, 0.8, 1)
        katsa.graphics.setColor(1, 1, 1, 1)
        katsa.graphics.rectangle('fill', 10, 10, 50, 50)
        drawn = true
    end)
    self:check(drawn, 'Drawing renders into the second window and returns')
    local mainWidth = katsa.window.getWidth()
    katsa.graphics.clear(0, 0, 0, 1)
    self:check(katsa.window.getWidth() == mainWidth and katsa.graphics.getWidth() == mainWidth, 'The main window is current again after drawing elsewhere')
    self:check(not pcall(window.draw, window, function() error('boom') end) and katsa.graphics.getWidth() == mainWidth, 'An error inside draw still restores the main window')
    window:setOpacity(0.5)
    self:check(window:getOpacity() <= 1, 'Window opacity can be set')
    window:close()
    self:check(not window:isOpen() and not pcall(window.draw, window, function() end), 'A closed window rejects drawing')
end

return Module
