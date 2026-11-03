local Node = require('../../nodes')
local ScrollBar = require('../scrolling.scrollBar')
local Canvas = require('../layout.scrollCanvas')

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
    dragWithMouse = {
        hint = 'Swipe-scroll with the mouse (hold and drag the content). Touch always swipes; the mouse only does when this is on. The scrollbar thumb and wheel work either way.',
    },
    inertia = {
        min = 0,
        max = 1,
        hint = 'How far the content keeps gliding after a swipe. 0 stops dead, 1 glides for a long time.',
    },
    overscroll = {
        min = 0,
        max = 1,
        hint = 'Rubber-band stretch past the ends as a fraction of the window size. 0 hard stops, 0.25 feels like a phone list.',
    },
    bounceSpeed = {
        min = 1,
        max = 40,
        hint = 'How quickly the stretch springs back after release (per second).',
        visibleWhen = function(target)
            return (target.overscroll or 0) > 0
        end,
    },
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
    self.dragWithMouse = self.dragWithMouse == true
    self.inertia = self.inertia or 0.6
    self.overscroll = self.overscroll or 0.25
    self.bounceSpeed = self.bounceSpeed or 14
    self._overX, self._overY, self._exX, self._exY, self._vx, self._vy = 0, 0, 0, 0, 0, 0
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
    return (self._windowX or 0) - self.scrollX - (self._overX or 0)
end

function Class:getChildOffset()
    return -self.scrollY - (self._overY or 0)
end

-- Rubber-band curve: raw finger excess -> displayed stretch, bounded by `limit`.
local function rubber(excess, limit)
    if limit <= 0 or excess == 0 then
        return 0
    end
    local sign = excess < 0 and -1 or 1
    excess = math.abs(excess)
    return sign * limit * excess / (excess + limit)
end

local function clamp(value, low, high)
    return math.max(low, math.min(high, value))
end

-- Moves one axis by `delta` pixels, keeping the part beyond the ends as elastic excess.
local function moveAxis(node, axis, delta)
    local x = axis == 'X'
    local scroll = x and node.scrollX or node.scrollY
    local excess = x and node._exX or node._exY
    local window = x and node._windowWidth or node._windowHeight
    local maximum = math.max(0, node.absoluteCanvasSize[x and 1 or 2] - window)
    local position = scroll + excess + delta
    scroll = clamp(position, 0, maximum)
    excess = node.overscroll > 0 and position - scroll or 0
    if x then
        node.scrollX, node._exX = scroll, excess
    else
        node.scrollY, node._exY = scroll, excess
    end
    return rubber(excess, node.overscroll * window)
end

function Class:hasMotion()
    return self._vx ~= 0 or self._vy ~= 0 or self._exX ~= 0 or self._exY ~= 0
end

function Class:stopMotion()
    self._vx, self._vy = 0, 0
end

-- Applies a swipe delta (content follows the finger) with elastic ends.
function Class:dragBy(ui, deltaY, deltaX)
    ui:layout()
    local x, y = Canvas.axes(self)
    local overX = x and moveAxis(self, 'X', deltaX or 0) or 0
    local overY = y and moveAxis(self, 'Y', deltaY or 0) or 0
    self._overX, self._overY = overX, overY
    self.canvasPosition[1], self.canvasPosition[2] = self.scrollX, self.scrollY
    self._lastScrollX, self._lastScrollY = self.scrollX, self.scrollY
    self._lastCanvasX, self._lastCanvasY = self.scrollX, self.scrollY
    ui:invalidate()
end

-- Inertia glide and spring-back, advanced by UI:update while hasMotion() is true.
function Class:stepMotion(ui, dt)
    dt = math.min(dt, 1 / 20)
    local friction = 0.5 + 8 * (1 - self.inertia) ^ 2
    local x, y = Canvas.axes(self)
    local spring = 1 - math.exp(-self.bounceSpeed * dt)
    for _, axis in ipairs({ 'X', 'Y' }) do
        local horizontal = axis == 'X'
        local key = horizontal and '_vx' or '_vy'
        local exKey = horizontal and '_exX' or '_exY'
        local velocity = self[key]
        if self.inertia <= 0 or not (horizontal and x or not horizontal and y) then
            velocity = 0
        end
        if self[exKey] ~= 0 then
            -- Past an end the spring takes over and swallows the remaining speed.
            velocity = velocity * math.exp(-self.bounceSpeed * dt * 0.5)
            self[exKey] = self[exKey] * (1 - spring)
            if math.abs(self[exKey]) < 0.4 then
                self[exKey] = 0
            end
        end
        velocity = velocity * math.exp(-friction * dt)
        if math.abs(velocity) < 6 then
            velocity = 0
        end
        self[key] = velocity
    end
    -- Content follows the finger direction, so the velocity is applied as a drag delta.
    local dx, dy = self._vx * dt, self._vy * dt
    local keepX, keepY = self._exX, self._exY
    self._exX, self._exY = 0, 0
    local overX = x and moveAxis(self, 'X', dx + keepX) or 0
    local overY = y and moveAxis(self, 'Y', dy + keepY) or 0
    -- Hitting an end without elastic stretch kills the speed on that axis.
    if self.overscroll <= 0 then
        local atX = self.scrollX <= 0 or self.scrollX >= math.max(0, self.absoluteCanvasSize[1] - self._windowWidth)
        local atY = self.scrollY <= 0 or self.scrollY >= math.max(0, self.absoluteCanvasSize[2] - self._windowHeight)
        self._vx = atX and 0 or self._vx
        self._vy = atY and 0 or self._vy
    end
    self._overX, self._overY = overX, overY
    self.canvasPosition[1], self.canvasPosition[2] = self.scrollX, self.scrollY
    self._lastScrollX, self._lastScrollY = self.scrollX, self.scrollY
    self._lastCanvasX, self._lastCanvasY = self.scrollX, self.scrollY
    ui:invalidate()
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
        self:stopMotion()
        self._swipe = id ~= 'mouse' or self.dragWithMouse
        self._swipeTime, self._vx, self._vy = ui.time, 0, 0
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
        elseif self._swipe then
            local dx, dy = self._pointerX - lx, self._pointerY - ly
            local dt = math.max(1 / 240, ui.time - self._swipeTime)
            self._swipeTime = ui.time
            -- Smoothed finger speed; it becomes the glide speed on release.
            self._vx = self._vx * 0.5 + dx / dt * 0.5
            self._vy = self._vy * 0.5 + dy / dt * 0.5
            self:dragBy(ui, dy, dx)
        end
        self._pointerX, self._pointerY = lx, ly
    elseif (phase == 'release' or phase == 'cancel') and self._scrollPointer == id then
        if not self._swipe or phase == 'cancel' or ui.time - (self._swipeTime or 0) > 0.1 then
            self._vx, self._vy = 0, 0
        end
        self._swipe = nil
        if self:hasMotion() then
            ui:wake(self)
        end
        self._pointerX, self._pointerY, self._scrollPointer = nil, nil, nil
        self._scrollAxis, self._scrollGrab = nil, nil
    end
end

return Class
