-- UI Styler plugin: style sheets for UI nodes.
--
--   local UIStyler = require('source.engine.plugins').require('uiStyler')
--   local styler = UIStyler.new(scene.ui)
--   styler:defineTheme('dark', UIStyler.themes.dark)
--   styler:defineTheme('light', UIStyler.themes.light)
--   styler:rule('Button', { backgroundColor = '$button', textColor = '$text', corner = '$corner' })
--   styler:rule('Button.primary', { backgroundColor = '$accent' })      -- class + tag
--   styler:rule('#Search', { stroke = { color = '$border', thickness = 1 } })
--   styler:setTheme('dark')           -- resolves tokens and styles every tracked root
--   styler:apply(panel)               -- style a new subtree later
--
-- See styler.lua for the selector grammar and the pseudo properties `corner` and `stroke`.
return {
    new = require('./styler').new,
    themes = { dark = require('./themes.dark'), light = require('./themes.light') },
}
