-- uiStyler: style files with several values per style, bare-tag selectors, extends.
local UI = require('source.engine.ui')

local Module = {}

function Module.run(self)
    local UIStyler = require('source.engine.plugins').require('uiStyler')
    local ui = UI.new(300, 200, self.manager.resources:scope())
    local panel = ui:create('Frame', { name = 'Panel', size = { 1, 0, 1, 0 } }, ui.content)
    local box = ui:create('Frame', { name = 'Box', backgroundTransparency = 0.9 }, panel)
    box:addTag('card')
    local styler = UIStyler.new(ui)
    styler:defineTheme('dark', { panel = { 0.1, 0.2, 0.3 } })
    styler:loadStyles('source/game/scenes/launcherShowcase/assets/styles')
    styler:style('base', { corner = 10, cornerScale = 0.25, backgroundTransparency = 0.5 })
    styler:style('card', { extends = 'base', backgroundColor = '$panel' })
    styler:setTheme('dark')
    styler:apply(panel)
    local radius
    for _, child in ipairs(box.children) do
        radius = child.className == 'UICorner' and child.radius or radius
    end
    self:check(radius and radius[1] == 0.25 and radius[2] == 10, 'one style sets corner and scale together')
    self:check(box.backgroundTransparency == 0.5 and box.backgroundColor[3] == 0.3, 'bare tag style extends another style')
    self:check(#styler.rules > 5, 'loadStyles reads every file of the styles directory')
end

return Module
