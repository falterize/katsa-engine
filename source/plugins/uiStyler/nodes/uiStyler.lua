-- UIStyler: the style sheet of a screen UI as a node, so its theme and style files show up in the
-- Explorer and Inspector. The scene needs `plugins = { 'uiStyler' }`.
--
--   local node = world:create('UIStyler', { theme = 'dark', stylesFolder = 'scene://styles' })
--   node:bind(scene.ui)                 -- the UI the sheet styles (a scene owns its UI, not the world)
--   node:getStyler():style('Button', { backgroundColor = '$button' })   -- code rules still work
--
-- Editing `theme` restyles every bound root; editing `stylesFolder` reloads the `*.lua` style files
-- of that folder (a table of rules or a list of { selector, values }, see the plugin guide).
local Plugins = require('source.engine.plugins')

local Definition = {
    base = 'Node',
    properties = {
        theme = {
            default = 'dark',
            options = function()
                return Plugins.require('uiStyler').themeNames()
            end,
            hint = 'Token set the style rules read through $name values. Changing it restyles the UI.',
        },
        stylesFolder = {
            default = '',
            hint = 'Folder of style files (scene://styles). A file returns { selector = { property = value } }.',
        },
    },
}

function Definition.initialize(self)
    self._applied = {}
end

-- Connects the sheet to a screen UI (the scene's `ui`) and styles it.
function Definition:bind(ui)
    local UIStyler = Plugins.require('uiStyler')
    local styler = UIStyler.new(ui)
    for name, tokens in pairs(UIStyler.themes) do
        styler:defineTheme(name, tokens)
    end
    self._styler = styler
    self._ui = ui
    self._applied = {}
    self:_sync()
    return styler
end

-- Switches the theme from code and keeps the `theme` property in step.
function Definition:setTheme(name)
    self.theme = name
    self:_sync()
end

function Definition:getStyler()
    return self._styler
end

-- Applies the properties that changed since the last call.
function Definition:_sync()
    local styler, applied = self._styler, self._applied
    if not styler then
        return
    end
    if applied.stylesFolder ~= self.stylesFolder then
        applied.stylesFolder = self.stylesFolder
        if self.stylesFolder ~= '' then
            local folder = self.stylesFolder
            local resources = self._world and self._world.resources
            if resources and resources.canonical and folder:find('://', 1, true) then
                folder = resources:canonical(folder)
            end
            styler:loadStyles(folder)
        end
    end
    if applied.theme ~= self.theme and self.theme ~= '' then
        applied.theme = self.theme
        styler:setTheme(self.theme)
    end
end

function Definition:update()
    self:_sync()
end

return Definition
