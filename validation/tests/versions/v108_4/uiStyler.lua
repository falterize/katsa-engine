-- uiStyler plugin: selectors, specificity, tokens, pseudo properties and theme switching.
local UI = require('source.engine.ui')

local Module = {}

function Module.run(self)
    local UIStyler = require('source.engine.plugins').require('uiStyler')
    local ui = UI.new(400, 240, self.manager.resources:scope())
    local panel = ui:create('Frame', { name = 'Panel', size = { 1, 0, 1, 0 } }, ui.content)
    local plain = ui:create('Button', { name = 'Plain', text = 'a', textColor = { 1, 0, 0 } }, panel)
    local primary = ui:create('Button', { name = 'Primary', text = 'b' }, panel)
    primary:addTag('primary')
    local search = ui:create('TextLabel', { name = 'Search', text = 'c' }, panel)

    local styler = UIStyler.new(ui)
    styler:defineTheme('dark', { text = { 0.9, 0.9, 0.9 }, accent = { 0.2, 0.4, 0.9 }, corner = 6 })
    styler:defineTheme('light', { text = { 0.1, 0.1, 0.1 }, accent = { 0.1, 0.3, 0.8 }, corner = 3 })
    styler:rule('Button', { textColor = '$text', corner = '$corner' })
    styler:rule('Button.primary', { textColor = '$accent' })
    styler:rule('#Search', { textColor = { 0, 1, 0 }, stroke = { color = '$accent', thickness = 2 } })
    styler:setTheme('dark')
    styler:apply(panel)
    self:check(plain.textColor[1] == 0.9, 'class rule applies theme tokens')
    self:check(primary.textColor[3] == 0.9, 'class.tag rule outranks the class rule')
    self:check(search.textColor[2] == 1, 'name rule applies plain values')
    local corners = 0
    for _, child in ipairs(plain.children) do
        corners = corners + (child.className == 'UICorner' and 1 or 0)
    end
    self:check(corners == 1, 'corner pseudo property creates one UICorner')
    local stroke
    for _, child in ipairs(search.children) do
        stroke = child.className == 'UIStroke' and child or stroke
    end
    self:check(stroke ~= nil and stroke.color[3] == 0.9, 'stroke pseudo property resolves tokens')

    styler:setTheme('light')
    self:check(plain.textColor[1] == 0.1 and primary.textColor[3] == 0.8, 'theme switch restyles tracked roots')
    self:check(stroke.color[3] == 0.8, 'theme switch updates existing modifiers in place')
    local count = 0
    for _, child in ipairs(plain.children) do
        count = count + (child.className == 'UICorner' and 1 or 0)
    end
    self:check(count == 1, 'repeated styling does not duplicate modifiers')

    primary:removeTag('primary')
    styler:apply(panel)
    self:check(primary.textColor[1] == 0.1, 'removing a tag falls back to the lower-specificity rule')
    styler:rule('Button', {})
    styler:sheet({})
    styler:apply(panel)
    self:check(
        plain.textColor[1] == 1 and plain.textColor[2] == 0,
        'properties no rule sets are restored to their authored values'
    )
    self:check(
        not pcall(styler.setTheme, styler, 'missing') and not pcall(function()
            styler:rule('Button', { textColor = '$nope' })
            styler:apply(panel)
        end),
        'unknown themes and tokens are rejected'
    )
end

return Module
