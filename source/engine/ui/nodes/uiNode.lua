local ipairs = require('../../math.array').ipairs
local Node = require('../../nodes')

local UINode = Node.define('UINode', 'Node')
UINode.propertySchema = { layerGroup = {} }

function UINode.initialize(self)
    self.layerGroup = self.layerGroup or 'Default'
    self._backgroundAuthored = self.backgroundColor ~= nil or self.color ~= nil
    self._backgroundTransparencyAuthored = self.backgroundTransparency ~= nil
    -- Legacy coordinates are decoded once on creation, never a live API.
    self.position = self.position or { 0, self.x or 0, 0, self.y or 0 }
    self.size = self.size or { 0, self.width or 0, 0, self.height or 0 }
    self.x, self.y, self.width, self.height, self.scale = nil, nil, nil, nil
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
    self.anchorPoint = self.anchorPoint or { 0, 0 }
    self.visible, self.enabled = self.visible ~= false, self.enabled ~= false
end

function UINode.mount(ui, properties, parent)
    return ui:add(properties, parent)
end

function UINode:drawSelf(ui)
    local style = require('../style')
    local c = style.color(self, 'background')
    -- Zero-alpha built-in backgrounds cannot contribute color. Custom materials
    -- may ignore vertex alpha, so preserve their draw and the paint component.
    local alpha = c and style.alpha(self, 'background', c)
    if c and (alpha > 0 or self.material or katsa.graphics.getShader()) then
        katsa.graphics.push('all')
        require('../drawing.modifiers').bindGradient(ui, self, 'Background')
        katsa.graphics.setColor(c[1], c[2], c[3], alpha)
        katsa.graphics.rectangle('fill', self._x, self._y, self._width, self._height, self._radius)
        katsa.graphics.pop()
    end
    if self._paintComponent then
        self._paintComponent:draw(ui, self)
    end
end

function UINode:pointer(ui, phase, x, y, id) end

function UINode:getChildOffsetX()
    return 0
end

function UINode:getChildOffset()
    return 0
end

return UINode
