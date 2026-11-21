-- What the window shows when no scene could be started (nothing to run, no start scene named, or a
-- scene that failed to load): a short message. The reason goes to the console and the log.
local Empty = {}
Empty.__index = Empty

local MESSAGE = 'Could not start a scene.\nCheck the console for details.'

function Empty.new(manager, options)
    local reason = options and options.reason or 'No scene to run.'
    katsa.log.write('warn', reason, 'scene')
    return setmetatable({ manager = manager, settings = {}, reason = reason }, Empty)
end

function Empty:draw()
    local graphics = katsa.graphics
    local width, height = graphics.getDimensions()
    graphics.setColor(0.85, 0.85, 0.85)
    graphics.printf(MESSAGE, 0, height / 2 - 20, width, 'center')
    graphics.setColor(1, 1, 1)
end

return Empty
