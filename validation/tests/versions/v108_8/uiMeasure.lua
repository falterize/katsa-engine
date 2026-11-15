-- UINode:getAbsoluteSize/Position (interface units) and getPixelSize/Position (window pixels).
local UI = require('source.engine.ui')

local Module = {}

function Module.run(self)
    local ui = UI.new(800, 450, self.manager.resources:scope())
    local panel = ui:container({
        size = { 0.5, 0, 0, 100 },
        position = { 0, 20, 0, 30 },
    }, ui.content)
    local child = ui:container({
        size = { 1, -10, 0.5, 0 },
        position = { 0, 5, 0, 5 },
    }, panel)

    local w, h = panel:getAbsoluteSize()
    local x, y = panel:getAbsolutePosition()
    self:check(w == 400 and h == 100 and x == 20 and y == 30, 'Absolute size and position resolve UDim2 in interface units')

    local cw, ch = child:getAbsoluteSize()
    local cx, cy = child:getAbsolutePosition()
    self:check(cw == 390 and ch == 50 and cx == 25 and cy == 35, 'Absolute position is measured from the UI, not from the parent')

    ui.scale, ui.offsetX, ui.offsetY = 2, 10, 4
    local pw, ph = panel:getPixelSize()
    local px, py = panel:getPixelPosition()
    self:check(pw == 800 and ph == 200 and px == 50 and py == 64, 'Pixel size and position apply the UI scale and offset')

    local sx, sy = panel:getScreenCenter()
    self:check(sx == px + pw / 2 and sy == py + ph / 2, 'The screen centre is built from the pixel rectangle')

    local frame = ui:create('ScrollFrame', {
        size = { 0, 200, 0, 200 },
        position = { 0, 0, 0, 0 },
        canvasSize = { 0, 0, 0, 1000 },
    }, ui.content)
    local row = ui:container({ size = { 1, 0, 0, 50 }, position = { 0, 0, 0, 300 } }, frame)
    local _, before = row:getAbsolutePosition()
    frame.scrollY = 100
    ui:invalidate()
    local _, after = row:getAbsolutePosition()
    self:check(before - after == 100, 'Absolute position follows the scroll offset')

    panel:destroy()
    local dw, dh = panel:getAbsoluteSize()
    self:check(type(dw) == 'number' and type(dh) == 'number', 'A destroyed node still answers with numbers')
end

return Module
