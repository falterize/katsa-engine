-- TextLabel/TextBox font property: resolved like image paths, extension optional.
local UI = require('source.engine.ui')

local Module = {}

function Module.run(self)
    local resources = self.manager.resources:scope()
    local ui = UI.new(400, 240, resources)
    local plain = ui:rasterFont(20)
    local custom = ui:rasterFont(20, 'shared://fonts/test-font')
    self:check(custom ~= plain, 'font path yields a different font object than the default')
    self:check(
        custom:getWidth('Test') ~= plain:getWidth('Test'),
        'custom font has its own glyph metrics'
    )
    self:check(
        ui:rasterFont(20, 'shared://fonts/test-font') == custom,
        'custom fonts are cached per path and size'
    )
    self:check(
        ui:rasterFont(20, 'shared://fonts/missing-font') ~= nil,
        'a missing font falls back to the default font'
    )
    local label = ui:create(
        'TextLabel',
        { x = 0, y = 0, width = 200, height = 40, text = 'Hello', font = 'shared://fonts/test-font' },
        ui.content
    )
    ui:layout()
    require('source.engine.ui.drawing.text').prepare(ui, label)
    self:check(
        label._textLines ~= nil and label.font == 'shared://fonts/test-font',
        'TextLabel keeps the font property'
    )
    label.font = ''
    ui:layout()
    require('source.engine.ui.drawing.text').prepare(ui, label)
    self:check(label.font == '', 'font can be cleared back to the default')
end

return Module
