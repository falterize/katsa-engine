-- Colour picker pop-up: a hue/saturation wheel, a brightness bar and a live swatch. It edits one
-- vector property (`row`) of the selected nodes. While the mouse is held the nodes are updated
-- directly for a live preview; on release the original value is restored and the final colour is
-- committed through Ops:setProperty, so one drag is exactly one undo step.
local Kit = require('../support.kit')

local ColorPicker = {}
ColorPicker.__index = ColorPicker

local WHEEL, BAR, PAD = 160, 16, 12
local WIDTH = WHEEL + PAD * 2
local HEIGHT = PAD + WHEEL + 10 + BAR + 10 + 22 + PAD
local RESOLUTION = 128

local function hsvToRgb(h, s, v)
    local i = math.floor(h * 6)
    local f = h * 6 - i
    local p, q, t = v * (1 - s), v * (1 - f * s), v * (1 - (1 - f) * s)
    i = i % 6
    if i == 0 then
        return v, t, p
    elseif i == 1 then
        return q, v, p
    elseif i == 2 then
        return p, v, t
    elseif i == 3 then
        return p, q, v
    elseif i == 4 then
        return t, p, v
    end
    return v, p, q
end

local function rgbToHsv(r, g, b)
    local max, min = math.max(r, g, b), math.min(r, g, b)
    local delta = max - min
    local h = 0
    if delta > 0 then
        if max == r then
            h = ((g - b) / delta) % 6
        elseif max == g then
            h = (b - r) / delta + 2
        else
            h = (r - g) / delta + 4
        end
        h = h / 6
    end
    return h, max == 0 and 0 or delta / max, max
end

function ColorPicker.create(state, ui)
    return setmetatable({ state = state, ui = ui, wasDown = false, wasEscape = false }, ColorPicker)
end

function ColorPicker:isOpen()
    return self.window ~= nil
end

function ColorPicker:close()
    if self.window and not self.window.destroyed then
        self.window:destroy()
    end
    for _, image in ipairs({ self.wheelImage, self.barImage }) do
        image:release()
    end
    self.window, self.wheelImage, self.barImage, self.dragging = nil, nil, nil, nil
end

local function wheelData()
    local data = katsa.image.newImageData(RESOLUTION, RESOLUTION)
    local half = RESOLUTION / 2
    data:mapPixel(function(x, y)
        local dx, dy = (x + 0.5 - half) / half, (y + 0.5 - half) / half
        local radius = math.sqrt(dx * dx + dy * dy)
        if radius > 1 then
            return 0, 0, 0, 0
        end
        local hue = (math.atan2(dy, dx) / (2 * math.pi)) % 1
        local r, g, b = hsvToRgb(hue, radius, 1)
        return r, g, b, radius > 0.985 and (1 - radius) / 0.015 or 1
    end)
    return data
end

function ColorPicker:paintBar()
    local r, g, b = hsvToRgb(self.h, self.s, 1)
    local width = self.barData:getWidth()
    self.barData:mapPixel(function(x)
        local v = x / (width - 1)
        return r * v, g * v, b * v, 1
    end)
    self.barImage:replacePixels(self.barData)
end

-- The value written to the property: 0..255 or 0..1, whichever the property already uses.
function ColorPicker:current()
    local r, g, b = hsvToRgb(self.h, self.s, self.v)
    local scale = self.scale
    local value = { r * scale, g * scale, b * scale }
    if scale == 255 then
        for index = 1, 3 do
            value[index] = math.floor(value[index] + 0.5)
        end
    end
    if self.alpha then
        value[4] = self.alpha
    end
    return value
end

function ColorPicker:refresh()
    self:paintBar()
    local r, g, b = hsvToRgb(self.h, self.s, self.v)
    self.swatch.backgroundColor = { r, g, b, 1 }
    self.readout.text = ('%d, %d, %d'):format(r * 255 + 0.5, g * 255 + 0.5, b * 255 + 0.5)
    local half = WHEEL / 2
    local angle = self.h * 2 * math.pi
    self.marker.position = {
        0, PAD + half + math.cos(angle) * self.s * half - 5,
        0, PAD + half + math.sin(angle) * self.s * half - 5,
    }
    self.barMarker.position = { 0, PAD + self.v * (WHEEL - 4) - 1, 0, PAD + WHEEL + 8 }
    return self:current()
end

-- row: the property row ({ key, value }); x, y: where the pop-up opens.
function ColorPicker:show(row, x, y)
    self:close()
    local ui = self.ui
    local value = row.value
    local scale = (value[1] > 1 or value[2] > 1 or value[3] > 1) and 255 or 1
    self.row, self.scale, self.alpha = row, scale, value[4]
    self.h, self.s, self.v = rgbToHsv(value[1] / scale, value[2] / scale, value[3] / scale)
    self.original = {}
    for index = 1, #value do
        self.original[index] = value[index]
    end
    self.window = Kit.make(ui, 'Frame', {
        name = 'ColorPicker',
        position = {
            0, math.max(2, math.min(x, ui.width - WIDTH - 2)),
            0, math.max(2, math.min(y, ui.height - HEIGHT - 2)),
        },
        size = { 0, WIDTH, 0, HEIGHT },
        zIndex = 41,
    }, ui.content, 'window')
    local data = wheelData()
    self.wheelImage = katsa.graphics.newImage(data)
    data:release()
    self.wheel = Kit.make(ui, 'ImageRect', {
        position = { 0, PAD, 0, PAD },
        size = { 0, WHEEL, 0, WHEEL },
        image = self.wheelImage,
        backgroundTransparency = 1,
    }, self.window)
    self.barData = katsa.image.newImageData(64, 1)
    self.barImage = katsa.graphics.newImage(self.barData)
    self.bar = Kit.make(ui, 'ImageRect', {
        position = { 0, PAD, 0, PAD + WHEEL + 10 },
        size = { 0, WHEEL, 0, BAR },
        image = self.barImage,
        backgroundTransparency = 1,
    }, self.window)
    self.marker = Kit.make(ui, 'Frame', {
        size = { 0, 10, 0, 10 },
        backgroundColor = { 1, 1, 1, 1 },
        interactable = false,
        zIndex = 3,
    }, self.window)
    self.barMarker = Kit.make(ui, 'Frame', {
        size = { 0, 4, 0, BAR + 4 },
        backgroundColor = { 1, 1, 1, 1 },
        interactable = false,
        zIndex = 3,
    }, self.window)
    self.swatch = Kit.make(ui, 'Frame', {
        position = { 0, PAD, 0, HEIGHT - PAD - 22 },
        size = { 0, 40, 0, 22 },
        interactable = false,
    }, self.window)
    self.readout = Kit.label(ui, self.window, '', {
        position = { 0, PAD + 50, 0, HEIGHT - PAD - 22 },
        size = { 1, -(PAD * 2 + 50), 0, 22 },
        fontSize = 13,
    }, 'muted')
    self:refresh()
    self.state.styler:apply(self.window)
    self.wasDown = true -- the press that opened the picker must not start a drag
end

local function rectangle(node, mx, my)
    local x, y = node:getAbsolutePosition()
    local w, h = node:getAbsoluteSize()
    return mx >= x and mx <= x + w and my >= y and my <= y + h, x, y, w, h
end

function ColorPicker:preview(value)
    for _, node in ipairs(self.state.selection:items()) do
        pcall(function()
            node[self.row.key] = value
        end)
    end
end

function ColorPicker:dragTo(mx, my)
    if self.dragging == 'wheel' then
        local _, x, y, w, h = rectangle(self.wheel, mx, my)
        local dx, dy = (mx - (x + w / 2)) / (w / 2), (my - (y + h / 2)) / (h / 2)
        self.h = (math.atan2(dy, dx) / (2 * math.pi)) % 1
        self.s = math.min(1, math.sqrt(dx * dx + dy * dy))
    else
        local _, x, _, w = rectangle(self.bar, mx, my)
        self.v = math.max(0, math.min(1, (mx - x) / w))
    end
    self:preview(self:refresh())
end

-- Finishes a drag: put the original back, then commit once so undo gets a single step.
function ColorPicker:finish()
    self.dragging = nil
    self:preview(self.original)
    local value = self:current()
    self.state.panels.properties:commit(self.row.key, nil, nil, value)
    self.original = value
    self.row.value = value
end

function ColorPicker:update()
    local down = katsa.mouse.isDown(1) or katsa.mouse.isDown(2)
    local escape = katsa.keyboard.isDown('escape')
    if self.window then
        local ui = self.ui
        local mx, my = (katsa.mouse.getX() - ui.offsetX) / ui.scale, (katsa.mouse.getY() - ui.offsetY) / ui.scale
        if down and not self.wasDown then
            if rectangle(self.wheel, mx, my) then
                self.dragging = 'wheel'
            elseif rectangle(self.bar, mx, my) then
                self.dragging = 'bar'
            elseif not rectangle(self.window, mx, my) then
                self:close()
            end
        elseif escape and not self.wasEscape then
            self:close()
        end
        if self.window and self.dragging then
            if down then
                self:dragTo(mx, my)
            else
                self:finish()
            end
        end
    end
    self.wasDown, self.wasEscape = down, escape
end

return ColorPicker
