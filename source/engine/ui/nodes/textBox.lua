local Node = require('../../nodes')
local Editor = require('../widgets.textEditor')
local Focus = require('../widgets.textFocus')
local utf8 = require('utf8')
local Class = Node.define('TextBox', 'TextLabel')
Class.interactive, Class.dragCapture = true, true
Class.propertySchema = {
    placeholderText = {},
    readOnly = {},
    multiline = {},
    maxLength = { min = 0, integer = true },
}
local clipboard = { get = katsa.system.getClipboardText, set = katsa.system.setClipboardText }

function Class.initialize(self)
    self.text, self.placeholderText = self.text or '', self.placeholderText or ''
    self.multiline, self.readOnly = self.multiline == true, self.readOnly == true
    self.maxLength = self.maxLength or 0
    self.fontSize = self.fontSize or 16
    self._editor = Editor.new(self.text)
    self._scrollX, self._scrollY = 0, 0
    self:onDestroy(function()
        self:blur()
    end)
end

function Class:syncText()
    if self.text ~= self._editor.text then
        self._editor:set(self.text)
    end
    return self._editor
end

function Class:changedText()
    local old = self.text
    self.text = self._editor.text
    self.ui:invalidatePaint()
    if old ~= self.text then
        self:emit('textChanged', self, self.text)
        if self.onTextChanged then
            self.onTextChanged(self, self.text)
        end
    end
end

function Class:focus(selectAll)
    if Focus.current ~= self then
        if Focus.current then
            Focus.current:blur()
        end
        Focus.current = self
        self:syncText()
        self._repeatBefore = katsa.keyboard.hasKeyRepeat()
        katsa.keyboard.setKeyRepeat(true)
        katsa.mouse.setRelativeMode(false)
        self:emit('focused', self)
    end
    if selectAll then
        self._editor.anchor, self._editor.cursor = 0, #self.text
    end
    local ui = self.ui
    ui:layout()
    local x, y = ui:position(self)
    katsa.keyboard.setTextInput(
        true,
        x * ui.scale + ui.offsetX,
        y * ui.scale + ui.offsetY,
        self._width * ui.scale,
        self._height * ui.scale
    )
    ui:invalidatePaint()
end

function Class:blur()
    if Focus.current ~= self then
        return
    end
    Focus.current = nil
    self._dragging = nil
    katsa.keyboard.setTextInput(false)
    katsa.keyboard.setKeyRepeat(self._repeatBefore == true)
    self:emit('focusLost', self)
    if self.onFocusLost then
        self.onFocusLost(self)
    end
    if self.ui and not self.ui.released then
        self.ui:invalidatePaint()
    end
end

function Class:insertText(text)
    self:syncText():replace(text, self)
    self:changedText()
end

function Class:editKey(key)
    self:syncText()
    local mods = {
        ctrl = katsa.keyboard.isDown('lctrl', 'rctrl', 'lgui', 'rgui'),
        shift = katsa.keyboard.isDown('lshift', 'rshift'),
    }
    if key == 'escape' then
        self:blur()
    elseif key == 'return' or key == 'kpenter' then
        if self.multiline and not mods.ctrl then
            self:insertText('\n')
        else
            self:emit('submitted', self, self.text)
            if self.onSubmit then
                self.onSubmit(self, self.text)
            end
            self:blur()
        end
    else
        self._editor:key(key, mods, clipboard, self)
    end
    self:changedText()
    return true
end

function Class:lines()
    self:syncText()
    if self._lineText ~= self.text then
        self._lineText, self._lines = self.text, {}
        local at = 0
        for line in (self.text .. '\n'):gmatch('(.-)\n') do
            self._lines[#self._lines + 1] = { text = line, start = at }
            at = at + #line + 1
        end
    end
    return self._lines
end

function Class:pointer(ui, phase, x, y, id)
    if phase == 'release' or phase == 'cancel' then
        self._dragging = nil
        return
    end
    if phase ~= 'press' and (phase ~= 'move' or self._dragging ~= id) then
        return
    end
    if phase == 'press' then
        self:focus()
        self._dragging = id
    end
    local lines = self:lines()
    local font, scale = ui:rasterFont(self.fontSize)
    local lineHeight = font:getHeight() * scale
    local lx, ly = (x - ui.offsetX) / ui.scale, (y - ui.offsetY) / ui.scale
    local padding = self.padding or 6
    local top = self.multiline and self._y + padding or self._y + (self._height - lineHeight) / 2
    local line = lines[math.max(
        1,
        math.min(#lines, math.floor((ly - top + self._scrollY) / lineHeight) + 1)
    )]
    local target, at = lx - self._x - padding + self._scrollX, 0
    for offset, code in utf8.codes(line.text) do
        local finish = offset + #utf8.char(code) - 1
        local left, right =
            font:getWidth(line.text:sub(1, at)) * scale,
            font:getWidth(line.text:sub(1, finish)) * scale
        if target < (left + right) / 2 then
            break
        end
        at = finish
    end
    self._editor:move(line.start + at, phase == 'move' or katsa.keyboard.isDown('lshift', 'rshift'))
    if phase == 'press' then
        local now = katsa.timer.getTime()
        if self._clickTime and now - self._clickTime < 0.35 and math.abs(lx - self._clickX) < 4 then
            local right = self._editor:word(1)
            self._editor:move(self._editor:word(-1), false)
            self._editor:move(right, true)
            self._clickTime = nil
        else
            self._clickTime, self._clickX = now, lx
        end
    end
    ui:invalidatePaint()
end

function Class:drawSelf(ui)
    Node.getClass('Frame').drawSelf(self, ui)
    local lines, editor, g = self:lines(), self._editor, katsa.graphics
    local font, scale = ui:rasterFont(self.fontSize)
    local padding, height = self.padding or 6, font:getHeight() * scale
    local width = math.max(1, self._width - padding * 2)
    local active, row, column = Focus.current == self, 1, 0
    for index, line in ipairs(lines) do
        if editor.cursor >= line.start then
            row, column = index, editor.cursor - line.start
        end
    end
    local caret = font:getWidth(lines[row].text:sub(1, column)) * scale
    if active then
        self._scrollX = math.max(0, math.min(self._scrollX, caret))
        self._scrollX = math.max(self._scrollX, caret - width + 2)
        self._scrollY = math.max(0, math.min(self._scrollY, (row - 1) * height))
        self._scrollY = math.max(self._scrollY, row * height - self._height + padding * 2)
    end
    local x, y =
        self._x + padding - self._scrollX,
        (self.multiline and self._y + padding or self._y + (self._height - height) / 2)
            - self._scrollY
    g.push('all')
    local sx, sy = g.transformPoint(self._x, self._y)
    local ex, ey = g.transformPoint(self._x + self._width, self._y + self._height)
    g.intersectScissor(math.min(sx, ex), math.min(sy, ey), math.abs(ex - sx), math.abs(ey - sy))
    g.setFont(font)
    local a, b = editor:range()
    for index, line in ipairs(lines) do
        local top = y + (index - 1) * height
        if active and a ~= b and b > line.start and a <= line.start + #line.text then
            local left = font:getWidth(line.text:sub(1, math.max(0, a - line.start))) * scale
            local right = font:getWidth(line.text:sub(1, math.min(#line.text, b - line.start)))
                * scale
            if b > line.start + #line.text then
                right = right + 4
            end
            g.setColor(0.15, 0.4, 0.65, 0.9)
            g.rectangle('fill', x + left, top, right - left, height)
        end
        local color = self.textColor or { 1, 1, 1 }
        g.setColor(color[1], color[2], color[3], 1 - (self.textTransparency or 0))
        local tx, ty = require('../drawing.pixelGrid').snap(g, x, top)
        g.print(line.text, tx, ty, 0, scale, scale)
    end
    if self.text == '' and not active then
        g.setColor(0.55, 0.6, 0.65, 1)
        g.print(self.placeholderText, x, y, 0, scale, scale)
    end
    if active then
        g.setColor(1, 1, 1, 1)
        g.rectangle('fill', x + caret, y + (row - 1) * height, 1 / ui.density, height)
    end
    g.pop()
    require('../../graphics.state').reapplyScissor()
end

return Class
