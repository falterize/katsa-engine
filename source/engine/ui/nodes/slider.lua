local Node = require('../../nodes')

local Class = Node.define('Slider', 'Frame')
local trackColor = { 0.18, 0.25, 0.34, 1 }
local fillColor = { 0.25, 0.72, 1, 1 }
Class.interactive = true

function Class.initialize(self)
    self.min, self.max = self.min or 0, self.max or 1
    assert(self.max > self.min, 'Slider.max must exceed Slider.min')
    self.value = math.max(self.min, math.min(self.max, self.value or self.min))
end

function Class:drawSelf(ui)
    Class.base.drawSelf(self, ui)
    local g, x, y = katsa.graphics, self._x, self._y
    local t = (self.value - self.min) / (self.max - self.min)
    local length = math.max(0, self._width - 24)
    g.setColor(self.trackColor or trackColor)
    g.rectangle('fill', x + 12, y + self._height / 2 - 4, length, 8, 4)
    g.setColor(self.fillColor or fillColor)
    g.rectangle('fill', x + 12, y + self._height / 2 - 4, length * t, 8, 4)
    g.circle('fill', x + 12 + length * t, y + self._height / 2, 12)
end

function Class:pointer(ui, phase, x, y, id)
    if phase ~= 'press' and phase ~= 'move' then
        return
    end
    local lx = (x - ui.offsetX) / ui.scale
    local t = math.max(0, math.min(1, (lx - self._x - 12) / math.max(1, self._width - 24)))
    local value = self.min + (self.max - self.min) * t
    if value ~= self.value then
        self.value = value
        ui:invalidate()
        self:emit('changed', value, self)
    end
end

return Class
