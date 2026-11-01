local Display = require('source.engine.core.displayDpi')

local Config = {}

function Config.apply(settings, project)
    Display.initialize()
    local window = project.window or {}
    settings.identity = assert(project.identity, 'Project requires a stable save identity')
    settings.version = '11.5'
    settings.console = project.console == true
    settings.window.title = project.title or 'Katsa Game'
    settings.window.width, settings.window.height =
        Display.initialSize(window.width or 1280, window.height or 720)
    local scale = Display.systemScale()
    settings.window.minwidth =
        math.min(settings.window.width, math.floor((window.minwidth or 320) * scale + 0.5))
    settings.window.minheight =
        math.min(settings.window.height, math.floor((window.minheight or 240) * scale + 0.5))
    settings.window.resizable = true
    settings.window.highdpi = true
    settings.window.depth, settings.window.stencil = 24, 8
    settings.window.vsync = 0
    for key, value in pairs(window) do
        if key ~= 'width' and key ~= 'height' and key ~= 'minwidth' and key ~= 'minheight' then
            settings.window[key] = value
        end
    end
    settings.gammacorrect = false
    settings.modules.physics = true
    settings.modules.video = false
    settings.externalstorage = project.externalStorage == true
end

return Config
