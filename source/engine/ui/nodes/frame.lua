local ipairs = require('../../math.array').ipairs
local Node = require('../../nodes')

-- The drawn UI node: it can be hidden (`visible`), has a background and takes pointer input.
local Class = Node.define('Frame', 'UINode')

function Class.initialize(self)
    self._backgroundAuthored = self.backgroundColor ~= nil or self.color ~= nil
    self._backgroundTransparencyAuthored = self.backgroundTransparency ~= nil
    for _, channel in ipairs({ 'background', 'image', 'text' }) do
        local key = channel .. 'Color'
        local color = self[key] or (channel == 'background' and self.color)
        if color then
            if self[channel .. 'Transparency'] == nil then
                self[channel .. 'Transparency'] = 1 - (color[4] or 1)
            end
            self[key] = { color[1], color[2], color[3] }
        end
    end
    if not self.backgroundColor then
        self.backgroundColor = { 0, 0, 0 }
        if self.backgroundTransparency == nil then
            self.backgroundTransparency = 1
        end
    end
    self.interactable = self.interactable ~= false
    self.visible = self.visible ~= false
end

function Class:drawSelf(ui)
    local style = require('source.engine.ui.style')
    local c = style.color(self, 'background')
    -- Zero-alpha built-in backgrounds cannot contribute color. Custom materials
    -- may ignore vertex alpha, so preserve their draw and the paint component.
    local alpha = c and style.alpha(self, 'background', c)
    if c and (alpha > 0 or self.material or katsa.graphics.getShader()) then
        katsa.graphics.push('all')
        require('source.engine.ui.drawing.modifiers').bindGradient(ui, self, 'Background')
        katsa.graphics.setColor(c[1], c[2], c[3], alpha)
        katsa.graphics.rectangle('fill', self._x, self._y, self._width, self._height, self._radius)
        katsa.graphics.pop()
    end
    if self._paintComponent then
        self._paintComponent:draw(ui, self)
    end
end

return Class
