local Node = require('source.engine.nodes')
local ScrollBar = require('source.engine.ui.scrolling.scrollBar')

local Class = Node.define('ScrollFrame', 'Frame')
Class.scrollable = true
Class.interactive = true
Class.propertySchema = {
    scrollingDirection = { options = { 'X', 'Y', 'XY' } },
    scrollingEnabled = {},
    canvasSize = {},
    canvasPosition = {},
    automaticCanvasSize = { options = { 'None', 'X', 'Y', 'XY' } },
    absoluteCanvasSize = { readOnly = true },
    absoluteWindowSize = { readOnly = true },
    horizontalScrollBarInset = { options = { 'None', 'Always', 'ScrollBar' } },
    verticalScrollBarInset = { options = { 'None', 'Always', 'ScrollBar' } },
    scrollBarThickness = { min = 0, max = 64 },
    scrollBarImageColor3 = {},
    scrollBarImageTransparency = { min = 0, max = 1 },
    verticalScrollBarPosition = { options = { 'Left', 'Right' } },
    topImage = {},
    midImage = {},
    bottomImage = {},
}

function Class.initialize(self)
    self.scrollingDirection = self.scrollingDirection or 'Y'
    self.scrollingEnabled = self.scrollingEnabled ~= false
    self.scrollX, self.scrollY = self.scrollX or 0, self.scrollY or 0
    self.length = self.length or self.contentHeight or 0
    self.contentHeight = nil
    self.automaticLength = self.automaticLength == true
    self.canvasSize = self.canvasSize or { 0, 0, 0, self.length }
    self.canvasPosition = self.canvasPosition or { self.scrollX, self.scrollY }
    self.automaticCanvasSize = self.automaticCanvasSize or (self.automaticLength and 'Y' or 'None')
    self.absoluteCanvasSize, self.absoluteWindowSize = { 0, 0 }, { 0, 0 }
    self.horizontalScrollBarInset = self.horizontalScrollBarInset or 'None'
    self.verticalScrollBarInset = self.verticalScrollBarInset or 'None'
    self._lastScrollX, self._lastScrollY = self.scrollX, self.scrollY
    self._lastCanvasX, self._lastCanvasY = self.canvasPosition[1], self.canvasPosition[2]
    self._lastLength, self._lastCanvasHeight = self.length, self.canvasSize[4]
    self._lastAutomaticLength = self.automaticLength
    self.contentPadding = self.contentPadding or 0
    self.clip = self.clip ~= false
    self.scrollBarThickness = self.scrollBarThickness or 3
    self.scrollBarImageColor3 = self.scrollBarImageColor3 or { 0.45, 0.7, 0.9 }
    self.scrollBarImageTransparency = self.scrollBarImageTransparency or 0.35
    self.verticalScrollBarPosition = self.verticalScrollBarPosition or 'Right'
    self.topImage, self.midImage, self.bottomImage =
        self.topImage or '', self.midImage or '', self.bottomImage or ''
end

local function drawPart(ui, imagePath, x, y, width, height, horizontal)
    local g = katsa.graphics
    if imagePath == '' then
        g.rectangle('fill', x, y, width, height, math.min(width, height) * 0.5)
    else
        local image = ui.resources:image(imagePath)
        local iw, ih = image:getDimensions()
        if horizontal then
            g.draw(image, x + width, y, math.pi / 2, height / iw, width / ih)
        else
            g.draw(image, x, y, 0, width / iw, height / ih)
        end
    end
end

local function drawBar(node, ui, horizontal)
    local g = katsa.graphics
    local bar = ScrollBar.geometry(node, horizontal)
    local x, y, thumb = bar.x, bar.y, bar.length
    local thickness = node.scrollBarThickness
    local cap = math.min(thickness, thumb * 0.5)
    if horizontal then
        drawPart(ui, node.topImage, x, y, cap, thickness, true)
        drawPart(ui, node.midImage, x + cap, y, thumb - cap * 2, thickness, true)
        drawPart(ui, node.bottomImage, x + thumb - cap, y, cap, thickness, true)
    else
        drawPart(ui, node.topImage, x, y, thickness, cap)
        drawPart(ui, node.midImage, x, y + cap, thickness, thumb - cap * 2)
        drawPart(ui, node.bottomImage, x, y + thumb - cap, thickness, cap)
    end
end

function Class:drawScrollBar(ui)
    if
        self.scrollBarThickness <= 0
        or self.scrollBarImageTransparency >= 1
        or not (self._horizontalBar or self._verticalBar)
    then
        return
    end
    local g, color = katsa.graphics, self.scrollBarImageColor3
    g.push('all')
    g.setShader()
    g.setColor(color[1], color[2], color[3], 1 - self.scrollBarImageTransparency)
    if self._verticalBar then
        drawBar(self, ui, false)
    end
    if self._horizontalBar then
        drawBar(self, ui, true)
    end
    g.pop()
end

function Class:drawSelf(ui)
    Class.base.drawSelf(self, ui)
end

function Class:getChildOffsetX()
    return (self._windowX or 0) - self.scrollX
end

function Class:getChildOffset()
    return -self.scrollY
end

function Class:scrollBarAt(x, y)
    return ScrollBar.hit(self, x, y)
end

function Class:pointer(ui, phase, x, y, id)
    if not self.scrollingEnabled then
        self._pointerX, self._pointerY, self._scrollPointer = nil, nil, nil
        self._scrollAxis, self._scrollGrab = nil, nil
        return
    end
    local lx, ly = (x - ui.offsetX) / ui.scale, (y - ui.offsetY) / ui.scale
    if phase == 'press' then
        if self._scrollPointer ~= nil and self._scrollPointer ~= id then
            return
        end
        self._scrollPointer = id
        self._pointerX, self._pointerY = lx, ly
        local axis, thumb = self:scrollBarAt(lx, ly)
        self._scrollAxis = axis
        if axis then
            local horizontal = axis == 'X'
            local bar = ScrollBar.geometry(self, horizontal)
            local coordinate = horizontal and lx or ly
            self._scrollGrab = thumb and coordinate - (horizontal and bar.x or bar.y)
                or bar.length * 0.5
            if not thumb then
                ScrollBar.move(ui, self, axis, coordinate, self._scrollGrab)
            end
        end
    elseif phase == 'move' and self._scrollPointer == id and self._pointerY then
        if self._scrollAxis then
            -- Thumb motion follows the pointer; content dragging moves the canvas oppositely.
            ScrollBar.move(
                ui,
                self,
                self._scrollAxis,
                self._scrollAxis == 'X' and lx or ly,
                self._scrollGrab
            )
        else
            ui:scrollBy(self, self._pointerY - ly, self._pointerX - lx)
        end
        self._pointerX, self._pointerY = lx, ly
    elseif (phase == 'release' or phase == 'cancel') and self._scrollPointer == id then
        self._pointerX, self._pointerY, self._scrollPointer = nil, nil, nil
        self._scrollAxis, self._scrollGrab = nil, nil
    end
end

return Class
