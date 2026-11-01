local Node = require('source.engine.nodes')
local Class = Node.define('VirtualJoystick', 'Frame')

function Class.initialize(self)
    self.axisX, self.axisY = 0, 0
    self.knobRadius = self.knobRadius or 22
end

function Class:setAxes(x, y)
    assert(
        type(x) == 'number'
            and type(y) == 'number'
            and x == x
            and y == y
            and math.abs(x) < math.huge
            and math.abs(y) < math.huge,
        'Joystick axes must be finite'
    )
    local length = math.max(1, math.sqrt(x * x + y * y))
    x, y = x / length, y / length
    if self.axisX ~= x or self.axisY ~= y then
        self.axisX, self.axisY = x, y
        self.ui:invalidatePaint()
    end
end

function Class:drawSelf(ui)
    Class.base.drawSelf(self, ui)
    local radius = math.min(self._width, self._height) * 0.5
    local x, y = self._x + self._width * 0.5, self._y + self._height * 0.5
    local g = love.graphics
    g.push('all')
    g.setColor(0.1, 0.16, 0.22, 0.5)
    g.circle('fill', x, y, radius)
    g.setColor(0.5, 0.75, 1, 0.6)
    g.circle('line', x, y, radius)
    g.setColor(0.65, 0.85, 1, 0.8)
    g.circle('fill', x + self.axisX * radius, y - self.axisY * radius, self.knobRadius)
    g.pop()
end

return Class
