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

function UINode:pointer(ui, phase, x, y, id) end

-- Resolved layout in interface units (the UI's own logical resolution, before the window scales
-- it). Layout is lazy, so ask the owner to resolve it first. A node that is not laid out yet
-- (no UI) reports zeros.
function UINode:getAbsoluteSize()
    local ui = self.ui
    if not ui then
        return 0, 0
    end
    ui:layout()
    return self._width or 0, self._height or 0
end

-- Top-left corner measured from the top-left of the UI, scroll offsets included.
function UINode:getAbsolutePosition()
    local ui = self.ui
    if not ui then
        return 0, 0
    end
    return ui:position(self)
end

-- The same size in window pixels (interface units times the UI scale).
function UINode:getPixelSize()
    local width, height = self:getAbsoluteSize()
    local scale = self.ui and self.ui.scale or 1
    return width * scale, height * scale
end

-- The same corner in window pixels, letterbox offset included.
function UINode:getPixelPosition()
    local ui = self.ui
    local x, y = self:getAbsolutePosition()
    if not ui then
        return x, y
    end
    return ui.offsetX + x * ui.scale, ui.offsetY + y * ui.scale
end

-- Centre of the node in window pixels, where a finger would touch (screen UI only).
function UINode:getScreenCenter()
    local x, y = self:getPixelPosition()
    local width, height = self:getPixelSize()
    return x + width / 2, y + height / 2
end

-- Pointer verbs for code, the same three as ClickDetector3D: the node gets the events a touch at
-- its centre would give (`press`, `release`, and `click` when released over the node). `id` names the pointer ('code' by
-- default). They go straight to this node, whatever covers it; use `input:tap(x, y)` for a touch
-- that respects what is on top.
function UINode:press(id)
    local x, y = self:getScreenCenter()
    self.ui:pointer(self, 'press', x, y, id or 'code')
end

function UINode:release(id)
    local x, y = self:getScreenCenter()
    self.ui:pointer(self, 'release', x, y, id or 'code')
end

function UINode:click(id)
    self:press(id)
    self:release(id)
end

function UINode:getChildOffsetX()
    return 0
end

function UINode:getChildOffset()
    return 0
end

return UINode
