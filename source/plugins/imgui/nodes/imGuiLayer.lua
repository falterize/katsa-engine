-- ImGuiLayer: your own ImGui windows as a node. Connect to `gui` and draw with the `ig` API; the
-- scene needs `plugins = { 'imgui' }` and the platform's native library (see the guide).
--
--   local layer = world:create('ImGuiLayer', { theme = 'Dark', scale = 1 })
--   layer:connect('gui', function(ig)
--       if ig.begin('Spawner') then
--           if ig.button('Spawn') then spawn() end
--       end
--       ig.finish()
--   end)
--
-- The properties style every ImGui window of the scene (they belong to the one context).
local ffi = require('ffi')
local Layers = require('../layers')

local THEMES = { 'Dark', 'Light', 'Classic' }

local Definition = {
    base = 'Node',
    properties = {
        theme = {
            default = 'Dark',
            options = THEMES,
            hint = 'Colour set of every ImGui window in this scene.',
        },
        scale = {
            default = 1,
            min = 0.5,
            max = 3,
            hint = 'Size of text and widgets (1 = normal; 2 for high-density screens).',
        },
        showDemo = {
            default = false,
            hint = 'Open the Dear ImGui demo window: every widget with its code in the ImGui sources.',
        },
    },
}

function Definition.initialize(self)
    Layers[self] = true
end

-- Applies the style of this layer to the context the host owns.
function Definition:apply(gui)
    local C = gui.C
    if self._theme ~= self.theme then
        self._theme = self.theme
        local style = ({ Dark = C.igStyleColorsDark, Light = C.igStyleColorsLight, Classic = C.igStyleColorsClassic })[self.theme]
        style(nil)
    end
    gui.C.igGetStyle().FontScaleMain = self.scale
end

-- Draws the demo window when asked and lets scripts add theirs. Called by the host every frame.
function Definition:draw(gui)
    if self.enabled == false then
        return
    end
    self:apply(gui)
    if self.showDemo then
        local open = ffi.new('bool[1]', true)
        gui.C.igShowDemoWindow(open)
        self.showDemo = open[0]
    end
    self:emit('gui', gui.ig)
end

return Definition
