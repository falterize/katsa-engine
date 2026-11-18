-- Entering and leaving fullscreen keeps the cursor and redraws a few frames at the new size.
local Runtime = require('source.engine.core.runtime')

local Module = {}

function Module.run(self)
    katsa.mouse.setVisible(true)
    katsa.window.setFullscreen(true)
    self:check(katsa.mouse.isVisible(), 'The cursor stays visible after entering fullscreen')
    katsa.window.setFullscreen(false)
    katsa.window.setFullscreen(true)
    self:check(katsa.mouse.isVisible(), 'The cursor stays visible after entering fullscreen again')
    katsa.window.setFullscreen(false)

    Runtime.windowRedrawFrames = nil
    katsa.resize(katsa.graphics.getDimensions())
    self:check(Runtime.windowRedrawFrames == 4, 'A resize schedules redraws of the next frames')
    Runtime.windowRedrawFrames = nil
end

return Module
