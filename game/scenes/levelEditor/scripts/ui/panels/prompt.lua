-- A small modal question with one text field (Save as, Export as). Enter or OK accepts, Cancel
-- closes; the callback gets the text.
local Kit = require('../support.kit')

local Prompt = {}
Prompt.__index = Prompt

function Prompt.create(state, ui)
    local self = setmetatable({ state = state, ui = ui }, Prompt)
    self.dim = Kit.make(ui, 'Button', {
        name = 'PromptDim',
        position = { 0, 0, 0, 0 },
        size = { 1, 0, 1, 0 },
        zIndex = 60,
        visible = false,
    }, ui.content, 'dim')
    self.window = Kit.make(ui, 'Frame', {
        name = 'Prompt',
        anchorPoint = { 0.5, 0.5 },
        position = { 0.5, 0, 0.5, 0 },
        size = { 0, 380, 0, 118 },
        zIndex = 61,
        visible = false,
    }, ui.content, 'window')
    self.title = Kit.label(ui, self.window, '', { position = { 0, 14, 0, 10 }, size = { 1, -28, 0, 22 }, fontSize = 15 }, 'title')
    self.field = Kit.make(ui, 'TextBox', {
        position = { 0, 14, 0, 40 },
        size = { 1, -28, 0, 28 },
        fontSize = 14,
        text = '',
    }, self.window, 'field')
    self.field:connect('submitted', function(_, text)
        self:accept(text)
    end)
    local ok = Kit.button(ui, self.window, 'OK', 90, 26, function()
        self:accept(self.field.text)
    end, 'tool', 'on')
    ok.position = { 1, -200, 1, -38 }
    local cancel = Kit.button(ui, self.window, 'Cancel', 90, 26, function()
        self:hide()
    end, 'tool')
    cancel.position = { 1, -104, 1, -38 }
    return self
end

function Prompt:ask(title, default, callback)
    self.callback = callback
    self.title.text = title
    self.field.text = default or ''
    self.dim.visible, self.window.visible = true, true
    self.state.styler:apply(self.window)
    self.field:focus(true)
end

function Prompt:hide()
    self.dim.visible, self.window.visible = false, false
    self.callback = nil
end

function Prompt:accept(text)
    local callback = self.callback
    self:hide()
    if callback and text and text ~= '' then
        callback(text)
    end
end

function Prompt:update() end

return Prompt
